-- 0016: rider KYC loop (pack section 2) + driver licence fields.
-- Riders: not_submitted -> pending -> approved / rejected (admin decides).
-- Drivers: licence number + expiry stored for the licence detail screen.

alter table public.profiles
  add column if not exists rider_kyc_status text not null default 'not_submitted'
    check (rider_kyc_status in ('not_submitted','pending','approved','rejected')),
  add column if not exists rider_kyc_note text;

alter table public.drivers
  add column if not exists licence_no text,
  add column if not exists licence_expiry text;

-- submit_kyc gains optional licence fields (old calls unaffected).
create or replace function public.submit_kyc(
  p_category text, p_upi text, p_plate text, p_make text default null, p_model text default null,
  p_licence_no text default null, p_licence_expiry text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_category not in ('Bike','Auto','Mini','Sedan','SUV') then raise exception 'bad category'; end if;
  update public.drivers set vehicle_category = p_category, upi_id = nullif(p_upi,''),
    licence_no = p_licence_no, licence_expiry = p_licence_expiry,
    kyc_status = 'pending', kyc_notes = null where id = auth.uid();
  if not found then raise exception 'driver row missing'; end if;
  insert into public.vehicles(driver_id, category, make, model, plate)
    values (auth.uid(), p_category, p_make, p_model, p_plate);
end $$;

-- Rider submits selfie + ID (files land in kyc-docs/<uid>/ via the app).
create or replace function public.submit_rider_kyc()
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.profiles set rider_kyc_status = 'pending', rider_kyc_note = null
    where id = auth.uid();
end $$;

-- Admin decides rider KYC.
create or replace function public.decide_rider_kyc(p_user uuid, p_approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'admin only'; end if;
  update public.profiles set
    rider_kyc_status = case when p_approve then 'approved' else 'rejected' end,
    rider_kyc_note = p_note where id = p_user;
  insert into public.audit_log(actor, action, entity, entity_id, meta)
    values (auth.uid(), case when p_approve then 'rider_kyc.approved' else 'rider_kyc.rejected' end,
      'profiles', p_user::text, jsonb_build_object('note', p_note));
end $$;

-- Public counterparty card for a ride (names/ratings/vehicle only — no PII).
-- Riders see their driver; drivers see their rider. Anyone else gets nothing.
create or replace function public.ride_party_public(p_ride uuid)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v rides; out jsonb;
begin
  select * into v from public.rides where id = p_ride;
  if not found then raise exception 'ride not found'; end if;
  if auth.uid() = v.rider_id and v.driver_id is not null then
    select jsonb_build_object(
      'role', 'driver',
      'name', p.full_name,
      'rating', (select round(avg(stars)::numeric, 1) from public.ratings where to_id = v.driver_id),
      'trips', (select count(*) from public.rides where driver_id = v.driver_id and status = 'completed'),
      'plate', (select plate from public.vehicles where driver_id = v.driver_id order by created_at desc limit 1),
      'car', (select nullif(concat_ws(' ', make, model), '') from public.vehicles where driver_id = v.driver_id order by created_at desc limit 1),
      'category', (select vehicle_category from public.drivers where id = v.driver_id)
    ) into out from public.profiles p where p.id = v.driver_id;
    return out;
  elsif auth.uid() = v.driver_id then
    select jsonb_build_object(
      'role', 'rider',
      'name', p.full_name,
      'rating', (select round(avg(stars)::numeric, 1) from public.ratings where to_id = v.rider_id),
      'trips', (select count(*) from public.rides where rider_id = v.rider_id and status = 'completed')
    ) into out from public.profiles p where p.id = v.rider_id;
    return out;
  else
    raise exception 'not your ride';
  end if;
end $$;
