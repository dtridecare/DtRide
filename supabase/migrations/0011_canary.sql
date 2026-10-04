-- 0011: canary to diagnose why request_ride/create_ride 404.
-- Same RETURNS TABLE shape, trivial body, fresh name.
create or replace function public.ping_ride_test()
returns table (ride_id uuid, otp_plain text)
language sql stable security definer set search_path = public as $$
  select gen_random_uuid(), '1234'::text;
$$;
