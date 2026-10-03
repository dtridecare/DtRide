-- S4: coupons (platform-funded rider discounts), referrals, notifications inbox.
-- Launch cutover (manual, at go-live): update app_config set value = 'false' where key = 'allow_test_activate'.

-- ---------- coupons ----------
create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  discount_rs int not null check (discount_rs > 0),
  max_uses int, used_count int not null default 0,
  valid_from timestamptz not null default now(),
  valid_to timestamptz,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table public.coupons enable row level security;
create policy "coupons readable" on public.coupons for select using (is_active or is_admin());
create policy "coupons admin write" on public.coupons for all using (is_admin()) with check (is_admin());

insert into public.coupons(code, discount_rs, max_uses, valid_to) values
  ('WELCOME50', 50, 1000, now() + interval '90 days')
on conflict (code) do nothing;

alter table public.rides add column if not exists coupon_code text;

-- Validate a coupon for a fare; returns discount in Rs (0 if invalid).
create or replace function public.apply_coupon(p_code text, p_fare int)
returns int language plpgsql stable security definer set search_path = public as $$
declare v coupons;
begin
  select * into v from public.coupons where code = upper(trim(p_code));
  if not found then raise exception 'invalid coupon'; end if;
  if not v.is_active then raise exception 'coupon inactive'; end if;
  if v.valid_from > now() or (v.valid_to is not null and v.valid_to < now()) then
    raise exception 'coupon expired';
  end if;
  if v.max_uses is not null and v.used_count >= v.max_uses then
    raise exception 'coupon fully redeemed';
  end if;
  return least(v.discount_rs, p_fare);
end $$;

-- Record usage after a ride is created (best-effort, idempotent per ride).
create or replace function public.record_coupon_use(p_code text, p_ride uuid)
returns void language plpgsql security definer set search_path = public as $$
declare v coupons; v_rides rides;
begin
  select * into v_rides from public.rides where id = p_ride;
  if not found then raise exception 'ride not found'; end if;
  if v_rides.rider_id <> auth.uid() then raise exception 'not your ride'; end if;
  if v_rides.coupon_code is not null then return; end if;
  select * into v from public.coupons where code = upper(trim(p_code)) for update;
  if not found then raise exception 'invalid coupon'; end if;
  if not v.is_active then raise exception 'coupon inactive'; end if;
  if v.max_uses is not null and v.used_count >= v.max_uses then raise exception 'coupon fully redeemed'; end if;
  update public.coupons set used_count = used_count + 1 where id = v.id;
  update public.rides set coupon_code = v.code where id = p_ride;
end $$;

-- ---------- referrals ----------
alter table public.profiles add column if not exists referral_code text unique;

update public.profiles set referral_code = upper(substr(md5(id::text), 1, 8))
  where referral_code is null;

create or replace function public.set_referral_code()
returns trigger language plpgsql as $$
begin
  if new.referral_code is null then
    new.referral_code := upper(substr(md5(new.id::text), 1, 8));
  end if;
  return new;
end $$;

drop trigger if exists profiles_set_referral_code on public.profiles;
create trigger profiles_set_referral_code
  before insert on public.profiles for each row execute function public.set_referral_code();

create table public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_id uuid not null references public.profiles(id),
  referee_id uuid not null references public.profiles(id),
  reward_status text not null default 'pending',
  created_at timestamptz not null default now(),
  unique (referee_id),
  check (referrer_id <> referee_id)
);

alter table public.referrals enable row level security;
create policy "referrals own read" on public.referrals for select using (
  referrer_id = auth.uid() or referee_id = auth.uid() or is_admin());

-- Claim someone else's code (once per account, never self).
create or replace function public.claim_referral(p_code text)
returns void language plpgsql security definer set search_path = public as $$
declare v_ref uuid;
begin
  select id into v_ref from public.profiles where referral_code = upper(trim(p_code));
  if not found then raise exception 'invalid referral code'; end if;
  if v_ref = auth.uid() then raise exception 'cannot refer yourself'; end if;
  insert into public.referrals(referrer_id, referee_id)
    values (v_ref, auth.uid())
  on conflict (referee_id) do nothing;
end $$;

-- ---------- notifications inbox ----------
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null, body text not null,
  kind text not null default 'info',
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc) where read_at is null;

alter table public.notifications enable row level security;
create policy "notifications own all" on public.notifications for all using (
  user_id = auth.uid() or is_admin()) with check (user_id = auth.uid());

create or replace function public.mark_notifications_read()
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.notifications set read_at = now()
    where user_id = auth.uid() and read_at is null;
  get diagnostics n = row_count;
  return n;
end $$;
