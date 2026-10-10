-- 0021: gate ride creation on rider KYC approval (single trigger covers
-- request_ride, create_ride and any future writers).
create or replace function public.check_rider_kyc()
returns trigger language plpgsql as $$
begin
  if (select rider_kyc_status from public.profiles where id = new.rider_id) <> 'approved' then
    raise exception 'rider kyc required';
  end if;
  return new;
end $$;

drop trigger if exists rides_rider_kyc on public.rides;
create trigger rides_rider_kyc
  before insert on public.rides for each row execute function public.check_rider_kyc();
