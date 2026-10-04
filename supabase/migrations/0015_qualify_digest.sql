-- 0015: pgcrypto lives in the extensions schema on this project, but our
-- functions pin search_path=public, so bare digest() never resolves.
-- Schema-qualify it (confirmed text,text overload in extensions).

drop function if exists public.ping_ride_test();
drop table if exists public.cache_probe;

create or replace function public.request_ride(
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
    encode(extensions.digest(v_otp, 'sha256'), 'hex'), now() + interval '30 minutes', p_idempotency)
  returning id, v_otp;
end $$;

create or replace function public.verify_otp_and_start_ride(p_ride uuid, p_otp text)
returns public.rides language plpgsql security definer set search_path = public as $$
declare v_ride rides; v_sub driver_subscriptions;
begin
  select * into v_ride from rides where id = p_ride for update;
  if not found then raise exception 'ride not found'; end if;
  if v_ride.status not in ('accepted','arrived') then raise exception 'bad state: %', v_ride.status; end if;
  if v_ride.driver_id is null or v_ride.driver_id <> auth.uid() then raise exception 'not your ride'; end if;
  if v_ride.otp_expires_at < now() then raise exception 'otp expired'; end if;
  if v_ride.otp_attempts >= 5 then raise exception 'too many attempts'; end if;
  if v_ride.start_otp_hash <> encode(extensions.digest(p_otp, 'sha256'), 'hex') then
    update rides set otp_attempts = otp_attempts + 1 where id = p_ride;
    raise exception 'wrong otp';
  end if;
  select * into v_sub from driver_subscriptions
    where driver_id = auth.uid() and status='active'
      and credits_used < credits_total and now() < expires_at
    order by expires_at asc limit 1 for update;
  if not found then raise exception 'no active subscription credits'; end if;
  update driver_subscriptions set credits_used = credits_used + 1 where id = v_sub.id;
  insert into credit_ledger(driver_id, subscription_id, ride_id, delta, reason)
    values (auth.uid(), v_sub.id, p_ride, -1, 'ride_started');
  update rides set status='started', started_at=now() where id = p_ride returning * into v_ride;
  return v_ride;
end $$;

create or replace function public.regenerate_otp(p_ride uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v rides; v_otp text;
begin
  select * into v from public.rides where id = p_ride for update;
  if not found then raise exception 'ride not found'; end if;
  if v.rider_id <> auth.uid() then raise exception 'not your ride'; end if;
  if v.status not in ('accepted','arrived') then raise exception 'bad state: %', v.status; end if;
  v_otp := (floor(random() * 9000) + 1000)::int::text;
  update public.rides set start_otp_hash = encode(extensions.digest(v_otp, 'sha256'), 'hex'),
    otp_attempts = 0, otp_expires_at = now() + interval '10 minutes' where id = p_ride;
  return v_otp;
end $$;

-- create_ride (legacy name): same digest fix.
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
    encode(extensions.digest(v_otp, 'sha256'), 'hex'), now() + interval '30 minutes', p_idempotency)
  returning id, v_otp;
end $$;
