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
  const [{ count: pendingKyc }, { count: online }, { count: activeSubs }, { data: recent }, { data: drivers }] =
    await Promise.all([
      db.from('drivers').select('*', { count: 'exact', head: true }).eq('kyc_status', 'pending'),
      db.from('drivers').select('*', { count: 'exact', head: true }).eq('online', true),
      db.from('driver_subscriptions').select('*', { count: 'exact', head: true }).eq('status', 'active'),
      db.from('rides').select('id,status,category,mode,fare_estimate_rs,created_at')
        .order('created_at', { ascending: false }).limit(8),
      db.from('drivers').select('id,kyc_status,vehicle_category,upi_id,online,strikes,blocked_until,profiles!inner(full_name,phone)')
        .order('created_at', { ascending: false }).limit(20),
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
      <div className="card !p-0 overflow-hidden mt-6">
        <div className="px-5 py-4 font-semibold border-b border-slate-100">Drivers (latest 20)</div>
        <div className="overflow-x-auto">
        <table className="w-full min-w-[680px]">
          <thead><tr><th className="th">Driver</th><th className="th">Phone</th><th className="th">KYC</th><th className="th">Category</th><th className="th">Online</th><th className="th">Strikes</th></tr></thead>
          <tbody>
            {(drivers ?? []).map((d: {
              id: string; kyc_status: string; vehicle_category: string;
              online: boolean; strikes: number;
              profiles: { full_name: string | null; phone: string | null } | { full_name: string | null; phone: string | null }[] | null;
            }) => {
              const prof = Array.isArray(d.profiles) ? d.profiles[0] : d.profiles;
              return (
              <tr key={d.id}>
                <td className="td font-medium">{prof?.full_name ?? <span className="text-slate-400">—</span>}</td>
                <td className="td">{prof?.phone ?? '—'}</td>
                <td className="td">
                  <span className={`badge ${d.kyc_status === 'approved' ? 'bg-emerald-100 text-emerald-700' : d.kyc_status === 'rejected' ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-700'}`}>
                    {d.kyc_status}
                  </span>
                </td>
                <td className="td">{d.vehicle_category}</td>
                <td className="td">{d.online
                  ? <span className="inline-block h-2.5 w-2.5 rounded-full bg-emerald-500" title="online" />
                  : <span className="text-slate-300">—</span>}</td>
                <td className="td">{d.strikes}</td>
              </tr>
              );
            })}
          </tbody>
        </table>
        </div>
        {(drivers ?? []).length === 0 && <p className="p-5 text-sm text-slate-500">No drivers yet.</p>}
      </div>
    </div>
    </AdminGate>
  );
}
