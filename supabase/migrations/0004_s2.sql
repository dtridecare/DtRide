-- S2: fare config, ride lifecycle RPCs, bidding, realtime publication.

-- ---------- fare config (admin-set per category) ----------
create table public.fare_config (
  vehicle_category text primary key
    check (vehicle_category in ('Bike','Auto','Mini','Sedan','SUV')),
  base_rs int not null, per_km_rs numeric not null,
  per_min_rs numeric not null, min_fare_rs int not null default 30
);

insert into public.fare_config(vehicle_category, base_rs, per_km_rs, per_min_rs, min_fare_rs) values
 ('Bike', 20, 12, 1.0, 30), ('Auto', 25, 15, 1.5, 40),
 ('Mini', 40, 18, 2.0, 60), ('Sedan', 60, 22, 2.5, 90),
 ('SUV', 80, 28, 3.0, 120)
on conflict (vehicle_category) do nothing;

alter table public.fare_config enable row level security;
create policy "fare readable" on public.fare_config for select using (true);
create policy "fare admin write" on public.fare_config for all using (is_admin()) with check (is_admin());

alter table public.rides add column if not exists requeue_count int not null default 0;
alter table public.rides add column if not exists proposed_fare_rs int;

insert into public.app_config(key, value) values
  ('surge_default', '1.0'), ('arrival_radius_m', '300')
on conflict (key) do nothing;

-- ---------- realtime fan-out ----------
alter publication supabase_realtime add table public.rides;
alter publication supabase_realtime add table public.ride_offers;

-- ---------- party helper (bypasses RLS, used inside policies) ----------
create or replace function public.is_ride_party(p_ride uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.rides r
    where r.id = p_ride and (r.rider_id = auth.uid() or r.driver_id = auth.uid())
  ) or is_admin();
$$;

create policy "offers visible to parties" on public.ride_offers for select using (
  is_ride_party(ride_id));
create policy "locations visible to parties" on public.ride_locations for select using (
  is_ride_party(ride_id));

-- ---------- driver eligibility (shared by accept/offer/online checks) ----------
create or replace function public.assert_driver_eligible(p_category text)
returns void language plpgsql stable security definer set search_path = public as $$
declare v drivers;
begin
  select * into v from public.drivers where id = auth.uid();
  if not found then raise exception 'driver row missing'; end if;
  if v.kyc_status <> 'approved' then raise exception 'kyc not approved'; end if;
  if v.blocked_until is not null and v.blocked_until > now() then raise exception 'blocked'; end if;
  if not v.online then raise exception 'go online first'; end if;
  if v.vehicle_category <> p_category then raise exception 'category mismatch'; end if;
  if not has_active_subscription(auth.uid()) then raise exception 'no active subscription'; end if;
end $$;

-- ---------- create ride (rider). Generates OTP server-side, returns plain OTP once. ----------
create or replace function public.create_ride(
  p_pickup_lon double precision, p_pickup_lat double precision,
  p_drop_lon double precision, p_drop_lat double precision,
  p_pickup_text text, p_drop_text text,
  p_category text, p_mode text,
  p_distance_m int, p_duration_s int, p_fare_estimate int,
  p_proposed_fare int default null, p_idempotency text default null)
returns table (ride_id uuid, otp_plain text)
language plpgsql security definer set search_path = public as $$
declare v_otp text; v_band int; v_id uuid;
begin
  if p_category not in ('Bike','Auto','Mini','Sedan','SUV') then raise exception 'bad category'; end if;
  if p_mode not in ('fixed','bidding') then raise exception 'bad mode'; end if;
  if p_idempotency is not null then
    select id into v_id from public.rides where idempotency_key = p_idempotency and rider_id = auth.uid();
    if found then return query select v_id, null::text; return; end if;
  end if;
  if p_mode = 'bidding' then
    if p_proposed_fare is null then raise exception 'proposed fare required'; end if;
    select (value::text)::int into v_band from public.app_config where key = 'bidding_band_pct';
    if abs(p_proposed_fare - p_fare_estimate) * 100 > p_fare_estimate * v_band then
      raise exception 'proposed fare outside band';
    end if;
  end if;
  v_otp := (floor(random() * 9000) + 1000)::int::text;
  return query
  insert into public.rides(
    rider_id, mode, category, status,
    pickup, pickup_text, drop, drop_text,
    distance_m, duration_s, fare_estimate_rs, proposed_fare_rs,
    start_otp_hash, otp_expires_at, idempotency_key)
  values (
    auth.uid(), p_mode, p_category, 'requested',
    st_setsrid(st_makepoint(p_pickup_lon, p_pickup_lat), 4326)::geography, p_pickup_text,
    st_setsrid(st_makepoint(p_drop_lon, p_drop_lat), 4326)::geography, p_drop_text,
    p_distance_m, p_duration_s, p_fare_estimate, p_proposed_fare,
    encode(digest(v_otp, 'sha256'), 'hex'), now() + interval '30 minutes', p_idempotency)
  returning id, v_otp;
end $$;

-- ---------- accept ride (driver, first-wins claim) ----------
create or replace function public.accept_ride(p_ride uuid, p_lon double precision, p_lat double precision)
returns public.rides language plpgsql security definer set search_path = public as $$
declare v rides;
begin
  select * into v from public.rides where id = p_ride for update;
  if not found then raise exception 'ride not found'; end if;
  if v.status <> 'requested' then raise exception 'ride already taken'; end if;
  perform assert_driver_eligible(v.category);
  update public.rides set driver_id = auth.uid(), status = 'accepted',
    otp_expires_at = now() + interval '10 minutes' where id = p_ride returning * into v;
  update public.drivers set
    last_location = st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography,
    last_location_at = now() where id = auth.uid();
  return v;
end $$;

-- ---------- mark arrived (must be near pickup) ----------
create or replace function public.mark_arrived(p_ride uuid, p_lon double precision, p_lat double precision)
returns public.rides language plpgsql security definer set search_path = public as $$
declare v rides; v_rad int;
begin
  select * into v from public.rides where id = p_ride for update;
  if not found then raise exception 'ride not found'; end if;
  if v.driver_id <> auth.uid() then raise exception 'not your ride'; end if;
  if v.status <> 'accepted' then raise exception 'bad state: %', v.status; end if;
  select (value::text)::int into v_rad from public.app_config where key = 'arrival_radius_m';
  if st_distance(st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography, v.pickup) > v_rad then
    raise exception 'not at pickup yet';
  end if;
  update public.rides set status = 'arrived' where id = p_ride returning * into v;
  update public.drivers set
    last_location = st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography,
    last_location_at = now() where id = auth.uid();
  return v;
end $$;

-- ---------- bidding: driver counter-offer (max 3 rounds, inside band) ----------
create or replace function public.place_offer(p_ride uuid, p_amount int)
returns public.ride_offers language plpgsql security definer set search_path = public as $$
declare v rides; v_round int; v_band int; o ride_offers;
begin
  select * into v from public.rides where id = p_ride;
  if not found then raise exception 'ride not found'; end if;
  if v.mode <> 'bidding' then raise exception 'not a bidding ride'; end if;
  if v.status <> 'requested' then raise exception 'ride already taken'; end if;
  perform assert_driver_eligible(v.category);
  select (value::text)::int into v_band from public.app_config where key = 'bidding_band_pct';
  if abs(p_amount - v.fare_estimate_rs) * 100 > v.fare_estimate_rs * v_band then
    raise exception 'offer outside band';
  end if;
  select count(*) + 1 into v_round from public.ride_offers where ride_id = p_ride and driver_id = auth.uid();
  if v_round > 3 then raise exception 'max 3 rounds'; end if;
  insert into public.ride_offers(ride_id, driver_id, amount_rs, round)
    values (p_ride, auth.uid(), p_amount, v_round) returning * into o;
  return o;
end $$;

-- ---------- bidding: rider accepts an offer (revalidates driver) ----------
create or replace function public.accept_offer(p_ride uuid, p_offer uuid)
returns public.rides language plpgsql security definer set search_path = public as $$
declare v rides; o ride_offers; v_drivers drivers;
begin
  select * into v from public.rides where id = p_ride for update;
  if not found then raise exception 'ride not found'; end if;
  if v.rider_id <> auth.uid() then raise exception 'not your ride'; end if;
  if v.status <> 'requested' then raise exception 'ride already taken'; end if;
  select * into o from public.ride_offers where id = p_offer and ride_id = p_ride and status = 'pending';
  if not found then raise exception 'offer not available'; end if;
  select * into v_drivers from public.drivers where id = o.driver_id;
  if v_drivers.kyc_status <> 'approved' then raise exception 'driver unavailable'; end if;
  if v_drivers.blocked_until is not null and v_drivers.blocked_until > now() then raise exception 'driver unavailable'; end if;
  if not v_drivers.online then raise exception 'driver offline'; end if;
  if not has_active_subscription(o.driver_id) then raise exception 'driver has no credits'; end if;
  update public.ride_offers set status = 'rejected' where ride_id = p_ride and status = 'pending' and id <> p_offer;
  update public.ride_offers set status = 'accepted' where id = p_offer;
  update public.rides set driver_id = o.driver_id, status = 'accepted',
    fare_estimate_rs = o.amount_rs, otp_expires_at = now() + interval '10 minutes'
    where id = p_ride returning * into v;
  return v;
end $$;

-- ---------- cancel before OTP (rider or assigned driver) ----------
create or replace function public.cancel_ride(p_ride uuid, p_reason text default null)
returns public.rides language plpgsql security definer set search_path = public as $$
declare v rides;
begin
  select * into v from public.rides where id = p_ride for update;
  if not found then raise exception 'ride not found'; end if;
  if v.status in ('started','completed','cancelled_before_otp','cancelled_after_start') then
    raise exception 'cannot cancel in state %', v.status; end if;
  if v.rider_id <> auth.uid() and v.driver_id <> auth.uid() and not is_admin() then
    raise exception 'not your ride'; end if;
  update public.rides set status = 'cancelled_before_otp' where id = p_ride returning * into v;
  insert into public.audit_log(actor, action, entity, entity_id, meta)
    values (auth.uid(), 'ride.cancelled', 'rides', p_ride::text, jsonb_build_object('reason', p_reason));
  return v;
end $$;

-- ---------- nearby open requests for the calling driver ----------
create or replace function public.nearby_requests(p_lon double precision, p_lat double precision, p_radius_m int default 8000)
returns table (ride_id uuid, category text, mode text, fare_estimate int,
  proposed_fare int, distance_m int, pickup_text text, drop_text text,
  pickup_lon double precision, pickup_lat double precision, dist_m int)
language sql stable security definer set search_path = public as $$
  with me as (select vehicle_category from public.drivers where id = auth.uid())
  select r.id, r.category, r.mode, r.fare_estimate_rs, r.proposed_fare_rs,
    r.distance_m, r.pickup_text, r.drop_text,
    st_x(r.pickup::geometry), st_y(r.pickup::geometry),
    st_distance(r.pickup, st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography)::int
  from public.rides r, me
  where r.status = 'requested' and r.category = me.vehicle_category
    and st_dwithin(r.pickup, st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography, p_radius_m)
  order by r.pickup <-> st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography
  limit 20;
$$;

-- ---------- post GPS ping (assigned driver only) ----------
create or replace function public.post_location(p_ride uuid, p_lon double precision, p_lat double precision, p_speed numeric default null)
returns void language plpgsql security definer set search_path = public as $$
declare v rides;
begin
  select * into v from public.rides where id = p_ride;
  if not found then raise exception 'ride not found'; end if;
  if v.driver_id <> auth.uid() then raise exception 'not your ride'; end if;
  if v.status not in ('accepted','arrived','started') then raise exception 'bad state'; end if;
  insert into public.ride_locations(ride_id, loc, speed_kmh)
    values (p_ride, st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography, p_speed);
  update public.drivers set
    last_location = st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography,
    last_location_at = now() where id = auth.uid();
end $$;

-- ---------- expire stale requests (cron): requeue twice, then no_driver_found ----------
create or replace function public.expire_stale_rides()
returns int language plpgsql security definer set search_path = public as $$
declare v_timeout int; n int := 0; r record;
begin
  select (value::text)::int into v_timeout from public.app_config where key = 'accept_timeout_s';
  for r in select id, requeue_count from public.rides
           where status = 'requested' and created_at < now() - (v_timeout || ' seconds')::interval
           for update skip locked
  loop
    if r.requeue_count >= 2 then
      update public.rides set status = 'no_driver_found' where id = r.id;
    else
      update public.rides set requeue_count = requeue_count + 1, created_at = now() where id = r.id;
    end if;
    n := n + 1;
  end loop;
  return n;
end $$;
