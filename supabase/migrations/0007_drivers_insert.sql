-- 0007: driver signup could fail with 42501 because:
-- 1. Phone-OTP signups get role 'rider' from the trigger (no metadata),
--    so no drivers row exists when ensureProfile('driver') runs.
-- 2. drivers table had no INSERT policy at all.
-- 3. A plain upsert on an existing drivers row would attempt UPDATE,
--    which drivers must never allow self-service (KYC self-approval hole).
-- Fix: allow self INSERT only; app uses ON CONFLICT DO NOTHING.

create policy "drivers insert own" on public.drivers
  for insert with check (id = auth.uid());
