-- Nearby eligible drivers for dispatch (used by dispatch function + admin).
create or replace function public.nearby_drivers(p_pickup geography, p_radius_m int, p_category text)
returns table (driver_id uuid, dist_m int) language sql stable security definer set search_path = public as $$
  select d.id, st_distance(d.last_location, p_pickup)::int as dist_m
  from public.drivers d
  where d.online and d.kyc_status='approved'
    and d.vehicle_category = p_category
    and (d.blocked_until is null or d.blocked_until < now())
    and d.last_location is not null
    and st_dwithin(d.last_location, p_pickup, p_radius_m)
    and has_active_subscription(d.id)
  order by d.last_location <-> p_pickup limit 20;
$$;
