-- 0010: request_ride is create_ride under a fresh name.
-- The 0008 replace left PostgREST unable to route /rpc/create_ride (persistent
-- 404 although pg_proc shows a single correct signature, and the sibling
-- is_served from the same migration resolves fine). New name = fresh cache
-- entry. create_ride is left in place for backward compatibility.
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
    encode(digest(v_otp, 'sha256'), 'hex'), now() + interval '30 minutes', p_idempotency)
  returning id, v_otp;
end $$;
