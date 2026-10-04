-- 0008: service-area fencing + automated expiry sweeps.
-- Areas are circles (center + radius): add a row per city to expand.
-- Rides require pickup AND drop inside the SAME active area.

create table public.service_areas (
  id uuid primary key default gen_random_uuid(),
  name text not null, city text not null,
  center geography(Point,4326) not null,
  radius_m int not null check (radius_m > 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.service_areas enable row level security;
create policy "areas readable" on public.service_areas for select using (true);
create policy "areas admin write" on public.service_areas for all using (is_admin()) with check (is_admin());

-- Placeholder launch area; edit name/radius in Admin, or add your city.
insert into public.service_areas(name, city, center, radius_m) values
  ('Delhi NCR launch zone', 'Delhi',
   st_setsrid(st_makepoint(77.2090, 28.6139), 4326)::geography, 40000)
on conflict do nothing;

-- Is a point served? Returns the matching area name (or null).
create or replace function public.is_served(p_lon double precision, p_lat double precision)
returns table (served boolean, area_name text)
language sql stable security definer set search_path = public as $$
  select true, a.name from public.service_areas a
    where a.is_active
      and st_dwithin(a.center, st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography, a.radius_m)
    limit 1;
$$;

-- Gate create_ride: pickup + drop must sit inside one active area.
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
  if not exists (
    select 1 from public.service_areas a
    where a.is_active
      and st_dwithin(a.center, st_setsrid(st_makepoint(p_pickup_lon, p_pickup_lat),4326)::geography, a.radius_m)
      and st_dwithin(a.center, st_setsrid(st_makepoint(p_drop_lon, p_drop_lat),4326)::geography, a.radius_m)
  ) then raise exception 'outside service area'; end if;
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

-- ---------- automated sweeps (validated at push time) ----------
create extension if not exists pg_cron with schema extensions;

-- Stale requests: requeue x2 then no_driver_found (every minute).
select cron.schedule('expire-stale-rides', '* * * * *', $$select public.expire_stale_rides()$$);
-- Subscriptions past expiry (hourly).
select cron.schedule('expire-subscriptions', '0 * * * *', $$select public.expire_subscriptions()$$);
