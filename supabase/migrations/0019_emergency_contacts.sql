-- 0019: rider/driver emergency contacts for SOS (PRD safety).
create table public.emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null, phone text not null,
  created_at timestamptz not null default now(),
  check (char_length(phone) >= 7)
);

alter table public.emergency_contacts enable row level security;
create policy "contacts own all" on public.emergency_contacts for all using (
  user_id = auth.uid() or is_admin()) with check (user_id = auth.uid());
