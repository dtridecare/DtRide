-- 0018: rider KYC auto-approve switch (admin flips it live, no deploy).
insert into public.app_config(key, value) values
  ('rider_kyc_auto_approve', 'false')
on conflict (key) do nothing;

create or replace function public.submit_rider_kyc()
returns void language plpgsql security definer set search_path = public as $$
declare v_auto text;
begin
  select value::text into v_auto from public.app_config where key = 'rider_kyc_auto_approve';
  update public.profiles set
    rider_kyc_status = case when coalesce(trim(both '"' from v_auto), 'false') = 'true'
      then 'approved' else 'pending' end,
    rider_kyc_note = null
    where id = auth.uid();
end $$;
