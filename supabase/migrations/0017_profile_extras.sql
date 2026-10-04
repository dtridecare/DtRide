-- 0017: profile extras for pack signup screens.
alter table public.profiles
  add column if not exists email text,
  add column if not exists gender text check (gender is null or gender in ('Female','Male','Other')),
  add column if not exists city text;
alter table public.drivers
  add column if not exists home_city text;
