import { supabaseAdmin } from '../lib/supabase';
import { AdminGate } from '../lib/AdminGate';

export const dynamic = 'force-dynamic';

const STATS = [
  { key: 'kyc', label: 'Pending KYC', color: 'bg-amber-500' },
  { key: 'online', label: 'Drivers Online', color: 'bg-emerald-500' },
  { key: 'subs', label: 'Active Subscriptions', color: 'bg-indigo-500' },
  { key: 'rides', label: 'Active Rides', color: 'bg-purple-500' },
] as const;

export default async function Home() {
  const db = supabaseAdmin as any;
  const [{ count: pendingKyc }, { count: online }, { count: activeSubs }, { data: recent }, { data: drivers }] =
    await Promise.all([
      db.from('drivers').select('*', { count: 'exact', head: true }).eq('kyc_status', 'pending'),
      db.from('drivers').select('*', { count: 'exact', head: true }).eq('online', true),
      db.from('driver_subscriptions').select('*', { count: 'exact', head: true }).eq('status', 'active'),
      db.from('rides').select('id,status,category,mode,fare_estimate_rs,created_at').order('created_at', { ascending: false }).limit(8),
      db.from('drivers').select('id,kyc_status,vehicle_category,online,strikes,blocked_until,profiles!inner(full_name,phone)').order('created_at', { ascending: false }).limit(20),
    ]);
  const values: Record<string, number | null> = { kyc: pendingKyc, online, subs: activeSubs, rides: recent?.length ?? 0 };

  return (
    <AdminGate>
      <div className="space-y-6">
        <h1 className="text-2xl font-bold text-slate-900">Dashboard</h1>
        <p className="text-sm text-slate-500 mb-6">Live platform overview — subscription model, no commission.</p>
        <div className="grid grid-cols-1 sm:grid-cols-3 lg:grid-cols-4 gap-4 mb-6">
          {STATS.map((s) => (
            <div key={s.key} className="card flex flex-col items-start gap-2 p-6">
              <span className={`w-10 h-10 rounded-lg flex items-center justify-center text-white font-bold text-lg ${s.color}`} />
              <div className="mt-2">
                <div className="text-2xl font-bold text-slate-900">{values[s.key] ?? '—'}</div>
                <div className="text-sm text-slate-500">{s.label}</div>
              </div>
            </div>
          ))}
        </div>
        <div className="card p-6">
          <div className="flex justify-between items-start mb-4">
            <h3 className="text-lg font-bold text-slate-900">Recent Rides</h3>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead className="text-slate-400 border-b border-slate-100">
                <tr><th className="th">Ride</th><th className="th">Status</th><th className="th">Category / Mode</th><th className="th">Fare</th><th className="th">Created</th></tr>
              </thead>
              <tbody>
                {(recent ?? []).map((r: any) => (
                  <tr key={r.id} className="border-b border-slate-50 hover:bg-slate-50/50">
                    <td className="px-4 py-3 font-mono text-sm">{r.id.slice(0, 8)}</td>
                    <td className="px-4 py-3"><span className={`badge ${r.status === 'requested' ? 'bg-amber-100 text-amber-700' : r.status === 'accepted' ? 'bg-sky-100 text-sky-700' : r.status === 'arrived' ? 'bg-violet-100 text-violet-700' : r.status === 'started' ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-100 text-slate-700'}`}>{r.status}</span></td>
                    <td className="px-4 py-3">{r.category} · {r.mode}</td>
                    <td className="px-4 py-3 font-medium">₹{r.fare_estimate_rs ?? '?'}</td>
                    <td className="px-4 py-3 text-slate-500 text-sm">{new Date(r.created_at).toLocaleString()}</td>
                  </tr>
                ))}
                {recent.length === 0 && <tr><td className="px-4 py-3 text-slate-500" colSpan={5}>No rides yet.</td></tr>}
              </tbody>
            </table>
          </div>
        </div>
        <div className="card p-6">
          <div className="flex justify-between items-start mb-4">
            <h3 className="text-lg font-bold text-slate-900">Latest Drivers</h3>
          </div>
          <div className="space-y-2">
            {drivers.map((d: any) => {
              const prof = d.profiles?.[0];
              return (
                <div key={d.id} className="flex items-center gap-3 py-2 px-2 rounded-lg hover:bg-slate-50 transition-colors">
                  <div className="w-8 h-8 rounded-full bg-slate-200 flex items-center justify-center text-xs font-bold text-slate-600">
                    {prof?.full_name?.[0] || '?'}
                  </div>
                  <div className="flex-1">
                    <div className="flex justify-between">
                      <span className="text-sm font-medium text-slate-900">{prof.full_name ?? 'Unknown'}</span>
                      <span className={`text-xs font-medium ${d.kyc_status === 'approved' ? 'text-emerald-600' : d.kyc_status === 'rejected' ? 'text-red-600' : 'text-amber-600'}`}>{d.kyc_status}</span>
                    </div>
                    <div className="flex items-center gap-2 text-sm text-slate-500">
                      <span className={`inline-block h-1 w-1 rounded-full ${d.online ? 'bg-emerald-500' : 'bg-slate-400'}`}></span>
                      <span>{d.online ? 'Online' : 'Offline'}</span>
                    </div>
                  </div>
                  <div className="flex items-center gap-2 text-sm text-slate-500">{d.vehicle_category}</td>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </AdminGate>
  );
}
