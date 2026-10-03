-- S3: ratings, SOS/disputes, push tokens, auto-block, RLS gap closure.

-- ---------- push tokens (FCM) ----------
create table public.push_tokens (
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null, platform text not null default 'android',
  created_at timestamptz not null default now(),
  primary key (user_id, token)
);
alter table public.push_tokens enable row level security;
create policy "tokens own all" on public.push_tokens for all using (
  user_id = auth.uid() or is_admin()) with check (user_id = auth.uid());

-- ---------- ratings: one per direction ----------
alter table public.ratings add constraint ratings_once unique (ride_id, from_id);

alter table public.ratings enable row level security;
-- (already enabled in 0001; re-enabling is a no-op)
create policy "ratings visible to parties" on public.ratings for select using (
  from_id = auth.uid() or to_id = auth.uid() or is_admin());

create or replace function public.submit_rating(p_ride uuid, p_stars int, p_tags text[] default '{}')
returns void language plpgsql security definer set search_path = public as $$
declare v rides;
begin
  if p_stars < 1 or p_stars > 5 then raise exception 'stars 1-5'; end if;
  select * into v from public.rides where id = p_ride;
  if not found then raise exception 'ride not found'; end if;
  if v.status <> 'completed' then raise exception 'ride not completed'; end if;
  if auth.uid() <> v.rider_id and auth.uid() <> v.driver_id then raise exception 'not your ride'; end if;
  insert into public.ratings(ride_id, from_id, to_id, stars, tags)
  values (p_ride, auth.uid(),
    case when auth.uid() = v.rider_id then v.driver_id else v.rider_id end,
    p_stars, coalesce(p_tags, '{}'))
  on conflict (ride_id, from_id) do update set stars = excluded.stars, tags = excluded.tags;
end $$;

-- ---------- OTP regenerate (rider, before start) ----------
create or replace function public.regenerate_otp(p_ride uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v rides; v_otp text;
begin
  select * into v from public.rides where id = p_ride for update;
  if not found then raise exception 'ride not found'; end if;
  if v.rider_id <> auth.uid() then raise exception 'not your ride'; end if;
  if v.status not in ('accepted','arrived') then raise exception 'bad state: %', v.status; end if;
  v_otp := (floor(random() * 9000) + 1000)::int::text;
  update public.rides set start_otp_hash = encode(digest(v_otp, 'sha256'), 'hex'),
    otp_attempts = 0, otp_expires_at = now() + interval '10 minutes' where id = p_ride;
  return v_otp;
end $$;

-- ---------- complete_ride + auto-block at strike limit ----------
create or replace function public.complete_ride(p_ride uuid, p_end_lon double precision, p_end_lat double precision)
returns public.rides language plpgsql security definer set search_path = public as $$
declare v_ride rides; v_dist int; v_dur int; v_flag text;
  v_lim int; v_hours int; v_strikes int;
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
    select (value::text)::int into v_lim from public.app_config where key = 'strikes_limit';
    select (value::text)::int into v_hours from public.app_config where key = 'block_hours';
    update drivers set strikes = strikes + 1 where id = auth.uid() returning strikes into v_strikes;
    if v_strikes >= v_lim then
      update drivers set online = false, blocked_until = now() + (v_hours || ' hours')::interval
        where id = auth.uid();
    end if;
  end if;
  return v_ride;
end $$;

-- ---------- SOS + disputes ----------
create or replace function public.raise_sos(p_ride uuid, p_lon double precision, p_lat double precision, p_note text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.sos_events(ride_id, user_id, loc, note)
    values (p_ride, auth.uid(),
      st_setsrid(st_makepoint(p_lon, p_lat), 4326)::geography, p_note);
end $$;

create or replace function public.raise_dispute(p_ride uuid, p_subject text, p_body text default null)
returns void language plpgsql security definer set search_path = public as $$
declare v rides;
begin
  select * into v from public.rides where id = p_ride;
  if not found then raise exception 'ride not found'; end if;
  if auth.uid() <> v.rider_id and auth.uid() <> v.driver_id and not is_admin() then
    raise exception 'not your ride'; end if;
  insert into public.support_tickets(user_id, ride_id, subject, body)
    values (auth.uid(), p_ride, p_subject, p_body);
end $$;

-- ---------- RLS gaps: admin visibility + ticket workflow ----------
create policy "sos admin read" on public.sos_events for select using (is_admin());
create policy "sos own read" on public.sos_events for select using (user_id = auth.uid());
create policy "tickets admin all" on public.support_tickets for all using (is_admin()) with check (is_admin());
create policy "tickets own read" on public.support_tickets for select using (user_id = auth.uid());
create policy "audit admin read" on public.audit_log for select using (is_admin());
