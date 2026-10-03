import { supabaseAdmin } from '../lib/supabase';
import AdminGate from '../lib/AdminGate';
import LoginForm from '../lib/LoginForm';

export const dynamic = 'force-dynamic';

const STATS = [
  { key: 'kyc', label: 'Pending KYC', color: 'bg-amber-500' },
  { key: 'online', label: 'Drivers online', color: 'bg-emerald-500' },
  { key: 'subs', label: 'Active subscriptions', color: 'bg-indigo-500' },
] as const;

export default async function Home() {
  const db = supabaseAdmin();
  const [{ count: pendingKyc }, { count: online }, { count: activeSubs }, { data: recent }] =
    await Promise.all([
      db.from('drivers').select('*', { count: 'exact', head: true }).eq('kyc_status', 'pending'),
      db.from('drivers').select('*', { count: 'exact', head: true }).eq('online', true),
      db.from('driver_subscriptions').select('*', { count: 'exact', head: true }).eq('status', 'active'),
      db.from('rides').select('id,status,category,mode,fare_estimate_rs,created_at')
        .order('created_at', { ascending: false }).limit(8),
    ]);
  const values: Record<string, number | null> = { kyc: pendingKyc, online, subs: activeSubs };

  return (
    <AdminGate signedOut={<LoginForm />}>
    <div>
      <h1 className="text-2xl font-bold mb-1">Dashboard</h1>
      <p className="text-sm text-slate-500 mb-6">Live platform overview — subscription model, no commission.</p>
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
        {STATS.map((s) => (
          <div key={s.key} className="card flex items-center gap-4">
            <span className={`h-11 w-11 rounded-lg ${s.color} opacity-90`} />
            <div>
              <div className="text-3xl font-bold">{values[s.key] ?? '—'}</div>
              <div className="text-sm text-slate-500">{s.label}</div>
            </div>
          </div>
        ))}
      </div>
      <div className="card !p-0 overflow-hidden">
        <div className="px-5 py-4 font-semibold border-b border-slate-100">Recent rides</div>
        <div className="overflow-x-auto">
        <table className="w-full min-w-[560px]">
          <thead><tr><th className="th">Ride</th><th className="th">Status</th><th className="th">Cat / Mode</th><th className="th">Fare</th><th className="th">Created</th></tr></thead>
          <tbody>
            {(recent ?? []).map((r: { id: string; status: string; category: string; mode: string; fare_estimate_rs: number | null; created_at: string }) => (
              <tr key={r.id}>
                <td className="td font-mono">{r.id.slice(0, 8)}</td>
                <td className="td"><span className="badge bg-slate-100 text-slate-700">{r.status}</span></td>
                <td className="td">{r.category} · {r.mode}</td>
                <td className="td">₹{r.fare_estimate_rs ?? '?'}</td>
                <td className="td text-slate-500">{new Date(r.created_at).toLocaleString()}</td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
        {(recent ?? []).length === 0 && <p className="p-5 text-sm text-slate-500">No rides yet.</p>}
      </div>
    </div>
    </AdminGate>
  );
}
