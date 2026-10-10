-- 0020: riders/drivers must be able to OPEN support tickets
-- (previously select-only; inserts were admin-only by omission).
create policy "tickets own insert" on public.support_tickets
  for insert with check (user_id = auth.uid());
