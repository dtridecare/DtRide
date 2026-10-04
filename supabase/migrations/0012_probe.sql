-- 0012: diagnose frozen PostgREST cache. If this table is visible via REST
-- but ping_ride_test still 404s, the issue is function-listing specifically.
create table if not exists public.cache_probe (
  id uuid primary key default gen_random_uuid(),
  note text
);
alter table public.cache_probe enable row level security;
drop policy if exists "probe readable" on public.cache_probe;
create policy "probe readable" on public.cache_probe for select using (true);
notify pgrst, 'reload schema';
notify pgrst, 'reload config';
