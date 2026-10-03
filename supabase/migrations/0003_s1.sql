-- S1: auto-profiles, KYC storage, gated online toggle, test purchase flow.
-- Test-mode purchases run entirely through RPCs until Razorpay keys exist.

-- Allow pending subscriptions (order created, payment not yet confirmed).
alter table public.driver_subscriptions
  drop constraint if exists driver_subscriptions_status_check;
alter table public.driver_subscriptions
  add constraint driver_subscriptions_status_check
  check (status in ('pending','active','expired','cancelled'));

insert into public.app_config(key, value) values
  ('allow_test_activate', 'true')
on conflict (key) do nothing;

-- ---------- auto-create profile + driver row on signup ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_role text;
begin
  v_role := coalesce((new.raw_user_meta_data ->> 'role'), 'rider');
  if v_role not in ('rider','driver','admin') then v_role := 'rider'; end if;
  insert into public.profiles(id, role, phone, full_name)
    values (new.id, v_role, new.phone, new.raw_user_meta_data ->> 'full_name')
    on conflict (id) do nothing;
  if v_role = 'driver' then
    insert into public.drivers(id) values (new.id) on conflict (id) do nothing;
  end if;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function public.handle_new_user();

-- ---------- storage buckets ----------
insert into storage.buckets(id, name, public)
  values ('kyc-docs','kyc-docs', false), ('avatars','avatars', true)
on conflict (id) do nothing;

-- kyc-docs: driver reads/writes own folder "<uid>/..."; admin reads all.
create policy "kyc own read" on storage.objects for select using (
  bucket_id = 'kyc-docs' and (owner = auth.uid() or public.is_admin()));
create policy "kyc own write" on storage.objects for insert with check (
  bucket_id = 'kyc-docs' and owner = auth.uid());
create policy "kyc own update" on storage.objects for update using (
  bucket_id = 'kyc-docs' and (owner = auth.uid() or public.is_admin()));
-- avatars: public read, owner write.
create policy "avatars public read" on storage.objects for select using (bucket_id = 'avatars');
create policy "avatars own write" on storage.objects for insert with check (
  bucket_id = 'avatars' and owner = auth.uid());

-- ---------- extra RLS for S1 self-service ----------
create policy "insert own profile" on public.profiles for insert with check (id = auth.uid());
create policy "drivers read own" on public.drivers for select using (id = auth.uid() or is_admin());
create policy "vehicles own all" on public.vehicles for all using (
  driver_id = auth.uid() or is_admin()) with check (driver_id = auth.uid() or is_admin());
create policy "payments own read" on public.payments for select using (
  driver_id = auth.uid() or is_admin());
create policy "config readable" on public.app_config for select using (true);
create policy "drivers admin write" on public.drivers for update using (is_admin());
create policy "subs admin write" on public.driver_subscriptions for update using (is_admin());

-- ---------- submit KYC (driver self-service, resets to pending) ----------
create or replace function public.submit_kyc(
  p_category text, p_upi text, p_plate text, p_make text default null, p_model text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_category not in ('Bike','Auto','Mini','Sedan','SUV') then raise exception 'bad category'; end if;
  update public.drivers set vehicle_category = p_category, upi_id = nullif(p_upi,''),
    kyc_status = 'pending', kyc_notes = null where id = auth.uid();
  if not found then raise exception 'driver row missing'; end if;
  insert into public.vehicles(driver_id, category, make, model, plate)
    values (auth.uid(), p_category, p_make, p_model, p_plate);
end $$;

-- ---------- admin KYC decision ----------
create or replace function public.decide_kyc(p_driver uuid, p_approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  update public.drivers set
    kyc_status = case when p_approve then 'approved' else 'rejected' end,
    kyc_notes = p_note where id = p_driver;
  insert into public.audit_log(actor, action, entity, entity_id, meta)
    values (auth.uid(), case when p_approve then 'kyc.approved' else 'kyc.rejected' end,
      'drivers', p_driver::text, jsonb_build_object('note', p_note));
end $$;

-- ---------- gated online toggle (KYC + credits + block enforced server-side) ----------
create or replace function public.set_online(p_online boolean, p_lon double precision default null, p_lat double precision default null)
returns void language plpgsql security definer set search_path = public as $$
declare v drivers;
begin
  select * into v from public.drivers where id = auth.uid();
  if not found then raise exception 'driver row missing'; end if;
  if p_online then
    if v.kyc_status <> 'approved' then raise exception 'kyc not approved'; end if;
    if v.blocked_until is not null and v.blocked_until > now() then raise exception 'blocked'; end if;
    if not has_active_subscription(auth.uid()) then raise exception 'no active subscription'; end if;
  end if;
  update public.drivers set online = p_online,
    last_location = case when p_lon is not null then st_setsrid(st_makepoint(p_lon, p_lat),4326)::geography else last_location end,
    last_location_at = case when p_lon is not null then now() else last_location_at end
    where id = auth.uid();
end $$;

-- ---------- subscription order (pending) + test activation ----------
create or replace function public.create_subscription_order(p_plan uuid)
returns table (subscription_id uuid, payment_id uuid, amount_rs int)
language plpgsql security definer set search_path = public as $$
declare v_plan subscription_plans; v_sub uuid; v_pay uuid;
begin
  select * into v_plan from public.subscription_plans where id = p_plan and is_active;
  if not found then raise exception 'plan not available'; end if;
  insert into public.driver_subscriptions(driver_id, plan_id, credits_total, status, expires_at)
    values (auth.uid(), p_plan, v_plan.ride_credits, 'pending', now() + (v_plan.validity_days || ' days')::interval)
    returning id into v_sub;
  insert into public.payments(driver_id, subscription_id, amount_rs, razorpay_order_id, status)
    values (auth.uid(), v_sub, v_plan.price_rs, 'test_' || replace(v_sub::text,'-',''), 'pending')
    returning id into v_pay;
  return query select v_sub, v_pay, v_plan.price_rs;
end $$;

-- Test-mode activation: flips pending -> active without real money.
-- Disable by setting app_config allow_test_activate = false before production.
create or replace function public.activate_test_subscription(p_subscription uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v_cfg text; v_sub driver_subscriptions; v_days int;
begin
  select value::text into v_cfg from public.app_config where key = 'allow_test_activate';
  if coalesce(trim(both '"' from v_cfg), 'false') <> 'true' then raise exception 'test activation disabled'; end if;
  select * into v_sub from public.driver_subscriptions
    where id = p_subscription and driver_id = auth.uid() and status = 'pending';
  if not found then raise exception 'pending subscription not found'; end if;
  select validity_days into v_days from public.subscription_plans where id = v_sub.plan_id;
  update public.driver_subscriptions set status = 'active', starts_at = now(),
    expires_at = now() + (v_days || ' days')::interval where id = p_subscription;
  update public.payments set status = 'completed', razorpay_payment_id = 'test_pay_' || replace(p_subscription::text,'-','')
    where subscription_id = p_subscription and status = 'pending';
end $$;

-- ---------- expire sweep (call from cron / edge scheduler) ----------
create or replace function public.expire_subscriptions()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.driver_subscriptions set status = 'expired'
    where status = 'active' and expires_at < now();
  get diagnostics n = row_count;
  return n;
end $$;
