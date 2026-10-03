import { createClient } from '@supabase/supabase-js';

// Service-role bypasses RLS — server/admin use only, never expose to riders/drivers.
export const supabaseAdmin = () =>
  createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!
  );
