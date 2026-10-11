-- Platform announcements banner shown on rider/driver home screens.
create table public.platform_announcements (
  id uuid default gen_random_uuid() primary key,
  title text not null,
  subtitle text,
  kind text not null check (kind in ('info','warn','error','success')),
  target_role text check (target_role in ('rider','driver','both')),
  expires_at timestamptz,
  is_pinned boolean default false,
  created_at timestamptz default now()
);

-- RLS: allow public read, admin write via edge function
create policy "Announcements public read" on public.platform_announcements for select using (true);
create policy "Announcements admin write" on public.platform_announcements for all to public with check (false);

-- Index for expiry filtering
create index "idx_announcements_expires" on public.platform_announcements (expires_at);