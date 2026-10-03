import { supabaseAdmin } from '../lib/supabase';

export const dynamic = 'force-dynamic';

export default async function Home() {
  const db = supabaseAdmin();
  const [{ count: pendingKyc }, { count: online }, { count: activeSubs }] =
    await Promise.all([
      db.from('drivers').select('*', { count: 'exact', head: true }).eq('kyc_status', 'pending'),
      db.from('drivers').select('*', { count: 'exact', head: true }).eq('online', true),
      db.from('driver_subscriptions').select('*', { count: 'exact', head: true }).eq('status', 'active'),
    ]);
  return (
    <main>
      <h1>DT Ride — Admin</h1>
      <ul>
        <li>Pending KYC: {pendingKyc ?? '—'}</li>
        <li>Drivers online: {online ?? '—'}</li>
        <li>Active subscriptions: {activeSubs ?? '—'}</li>
      </ul>
      <p>Ride matching, OTP deduct and tracking land in S2/S3. S1 covers KYC → plans → purchase.</p>
    </main>
  );
}
