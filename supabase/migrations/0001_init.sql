-- DT Ride V1 schema: subscription credits, OTP-start deduct, PostGIS matching.
-- Run: supabase db push (or psql). Requires pgcrypto + postgis.

create extension if not exists "pgcrypto";
create extension if not exists "postgis";

-- NOTE: helpers (is_admin, has_active_subscription) are defined after the
-- core tables below: LANGUAGE SQL bodies are validated at CREATE time.

-- ---------- core tables ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('rider','driver','admin')),
  phone text, full_name text, avatar_url text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.drivers (
  id uuid primary key references public.profiles(id) on delete cascade,
  kyc_status text not null default 'pending' check (kyc_status in ('pending','approved','rejected')),
  kyc_notes text, vehicle_category text not null default 'Mini'
    check (vehicle_category in ('Bike','Auto','Mini','Sedan','SUV')),
  upi_id text, online boolean not null default false,
  last_location geography(Point,4326), last_location_at timestamptz,
  strikes int not null default 0, blocked_until timestamptz,
  created_at timestamptz not null default now()
);
create index drivers_geo_idx on public.drivers using gist (last_location);
create index drivers_online_idx on public.drivers (online, vehicle_category) where online;

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers(id) on delete cascade,
  category text not null, make text, model text, plate text not null,
  created_at timestamptz not null default now()
);

create table public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  name text not null, vehicle_category text not null,
  ride_credits int not null check (ride_credits > 0),
  price_rs int not null check (price_rs >= 0),
  validity_days int not null default 30,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.driver_subscriptions (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers(id) on delete cascade,
  plan_id uuid not null references public.subscription_plans(id),
  credits_total int not null, credits_used int not null default 0,
  starts_at timestamptz not null default now(),
  expires_at timestamptz not null,
  status text not null default 'active' check (status in ('active','expired','cancelled')),
  razorpay_order_id text, razorpay_payment_id text,
  created_at timestamptz not null default now(),
  check (credits_used <= credits_total)
);
create index driver_subs_driver_idx on public.driver_subscriptions (driver_id, status);

create table public.credit_ledger (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers(id) on delete cascade,
  subscription_id uuid references public.driver_subscriptions(id),
  ride_id uuid, delta int not null check (delta in (-1, 1)),
  reason text not null, created_at timestamptz not null default now()
);

create table public.rides (
  id uuid primary key default gen_random_uuid(),
  rider_id uuid not null references public.profiles(id),
  driver_id uuid references public.drivers(id),
  mode text not null default 'fixed' check (mode in ('fixed','bidding')),
  category text not null default 'Mini',
  status text not null default 'requested'
    check (status in ('requested','accepted','arrived','started','completed','cancelled_before_otp','cancelled_after_start','no_driver_found')),
  pickup geography(Point,4326) not null, pickup_text text,
  drop geography(Point,4326) not null, drop_text text,
  distance_m int, duration_s int, fare_estimate_rs int, fare_final_rs int,
  start_otp_hash text, otp_attempts int not null default 0, otp_expires_at timestamptz,
  started_at timestamptz, completed_at timestamptz,
  suspicious text, -- 'short' | 'off_route' | null
  idempotency_key text unique,
  created_at timestamptz not null default now()
);
create index rides_status_idx on public.rides (status, created_at desc);
create index rides_pickup_idx on public.rides using gist (pickup);

create table public.ride_offers (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id) on delete cascade,
  driver_id uuid not null references public.drivers(id),
  amount_rs int not null, round int not null default 1,
  status text not null default 'pending' check (status in ('pending','accepted','rejected','expired')),
  created_at timestamptz not null default now()
);

create table public.ride_locations (
  ride_id uuid not null references public.rides(id) on delete cascade,
  ts timestamptz not null default now(),
  loc geography(Point,4326) not null, speed_kmh numeric,
  primary key (ride_id, ts)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.drivers(id),
  subscription_id uuid references public.driver_subscriptions(id),
  amount_rs int not null, currency text not null default 'INR',
  razorpay_order_id text, razorpay_payment_id text, status text not null default 'pending',
  created_at timestamptz not null default now()
);

create table public.ratings (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides(id) on delete cascade,
  from_id uuid not null references public.profiles(id),
  to_id uuid not null references public.profiles(id),
  stars int not null check (stars between 1 and 5), tags text[] not null default '{}',
  created_at timestamptz not null default now()
);

create table public.sos_events (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid references public.rides(id),
  user_id uuid not null references public.profiles(id),
  loc geography(Point,4326), note text,
  created_at timestamptz not null default now()
);

create table public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  ride_id uuid references public.rides(id),
  subject text not null, body text, status text not null default 'open',
  created_at timestamptz not null default now()
);

create table public.app_config (
  key text primary key, value jsonb not null
);

create table public.audit_log (
  id uuid primary key default gen_random_uuid(),
  actor uuid references public.profiles(id),
  action text not null, entity text, entity_id text, meta jsonb,
  created_at timestamptz not null default now()
);

-- ---------- helpers ----------
-- SECURITY DEFINER so RLS policies can call them without recursion.
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.has_active_subscription(p_driver uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.driver_subscriptions s
    where s.driver_id = p_driver and s.status = 'active'
      and s.credits_used < s.credits_total and now() < expires_at
  );
$$;

-- ---------- seed config + plans ----------
insert into public.app_config(key, value) values
 ('accept_timeout_s','30'), ('search_radii_m','[3000,5000,8000]'),
 ('max_broadcast','10'), ('otp_length','4'), ('otp_attempts','5'),
 ('min_trip_m','300'), ('min_trip_s','120'), ('drop_geofence_m','500'),
 ('strikes_limit','3'), ('strikes_window_d','30'), ('block_hours','24'),
 ('grace_rides','0'), ('bidding_rounds','3'), ('bidding_band_pct','20'),
 ('location_interval_s','4')
on conflict (key) do nothing;

insert into public.subscription_plans(name, vehicle_category, ride_credits, price_rs, validity_days) values
 ('Bike 50', 'Bike', 50, 300, 30), ('Auto 50', 'Auto', 50, 400, 30),
 ('Mini 50', 'Mini', 50, 500, 30), ('Sedan 50', 'Sedan', 50, 800, 30),
 ('SUV 50', 'SUV', 50, 1000, 30);

-- ---------- RLS ----------
alter table public.profiles enable row level security;
alter table public.drivers enable row level security;
alter table public.vehicles enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.driver_subscriptions enable row level security;
alter table public.credit_ledger enable row level security;
alter table public.rides enable row level security;
alter table public.ride_offers enable row level security;
alter table public.ride_locations enable row level security;
alter table public.payments enable row level security;
alter table public.ratings enable row level security;
alter table public.sos_events enable row level security;
alter table public.support_tickets enable row level security;
alter table public.app_config enable row level security;
alter table public.audit_log enable row level security;

create policy "read own profile" on public.profiles for select using (id = auth.uid() or is_admin());
create policy "update own profile" on public.profiles for update using (id = auth.uid());
create policy "plans readable" on public.subscription_plans for select using (is_active or is_admin());
create policy "admin all" on public.app_config for all using (is_admin()) with check (is_admin());
create policy "rider own rides" on public.rides for select using (rider_id = auth.uid() or driver_id = auth.uid() or is_admin());
create policy "driver subs own" on public.driver_subscriptions for select using (driver_id = auth.uid() or is_admin());
create policy "ledger own" on public.credit_ledger for select using (driver_id = auth.uid() or is_admin());

-- Writes go through SECURITY DEFINER RPCs below (no direct insert/update policies for rides/ledger).

-- ---------- RPCs ----------
-- Start ride: verify OTP + deduct 1 credit atomically. Returns ride row.
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
  if v_ride.start_otp_hash <> encode(digest(p_otp, 'sha256'), 'hex') then
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

-- Complete ride with GPS proof; flags suspicious but completes.
create or replace function public.complete_ride(p_ride uuid, p_end_lon double precision, p_end_lat double precision)
returns public.rides language plpgsql security definer set search_path = public as $$
declare v_ride rides; v_dist int; v_dur int; v_flag text;
begin
  select * into v_ride from rides where id = p_ride for update;
  if v_ride.status <> 'started' then raise exception 'not started'; end if;
  if v_ride.driver_id <> auth.uid() then raise exception 'not your ride'; end if;
  select coalesce(max(st_distance(l.loc::geometry, v_ride.pickup::geometry))::int, 0) into v_dist
    from ride_locations l where l.ride_id = p_ride;
  v_dur := greatest(0, extract(epoch from (now() - v_ride.started_at))::int);
  if v_dist < 300 or v_dur < 120 then v_flag := 'short'; end if;
  if st_distance(
      st_setsrid(st_makepoint(p_end_lon, p_end_lat),4326)::geography, v_ride.drop) > 500
    then v_flag := coalesce(v_flag || '+', '') || 'off_route'; end if;
  update rides set status='completed', completed_at=now(), suspicious=v_flag where id = p_ride returning * into v_ride;
  if v_flag is not null then
    update drivers set strikes = strikes + 1 where id = auth.uid();
  end if;
  return v_ride;
end $$;

-- Admin refund 1 credit for a ride.
create or replace function public.refund_ride_credit(p_ride uuid, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_ride rides; v_led credit_ledger;
begin
  if not is_admin() then raise exception 'admin only'; end if;
  select * into v_ride from rides where id = p_ride;
  select * into v_led from credit_ledger where ride_id = p_ride and delta = -1 limit 1;
  if not found then raise exception 'no deduction to refund'; end if;
  if exists (select 1 from credit_ledger where ride_id = p_ride and delta = 1) then
    raise exception 'already refunded'; end if;
  update driver_subscriptions set credits_used = greatest(0, credits_used - 1) where id = v_led.subscription_id;
  insert into credit_ledger(driver_id, subscription_id, ride_id, delta, reason)
    values (v_led.driver_id, v_led.subscription_id, p_ride, 1, coalesce(p_note,'admin_refund'));
end $$;
