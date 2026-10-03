'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
import AdminGate from '../../lib/AdminGate';

const db = () =>
  createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);

type Ride = {
  id: string; status: string; category: string; mode: string;
  fare_estimate_rs: number | null; suspicious: string | null;
  created_at: string;
};

const STATUS_COLORS: Record<string, string> = {
  requested: 'bg-amber-100 text-amber-700',
  accepted: 'bg-sky-100 text-sky-700',
  arrived: 'bg-violet-100 text-violet-700',
  started: 'bg-emerald-100 text-emerald-700',
};

export default function RidesPage() {
  const [rides, setRides] = useState<Ride[]>([]);
  const [err, setErr] = useState('');

  useEffect(() => {
    const c = db();
    const load = async () => {
      const { data, error } = await c.from('rides').select(
        'id,status,category,mode,fare_estimate_rs,suspicious,created_at')
        .in('status', ['requested', 'accepted', 'arrived', 'started'])
        .order('created_at', { ascending: false }).limit(50);
      if (error) setErr(error.message);
      else setRides((data ?? []) as Ride[]);
    };
    load();
    const ch = c.channel('admin-rides')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rides' }, load)
      .subscribe();
    return () => { c.removeChannel(ch); };
  }, []);

  return (
    <AdminGate>
      <h1 className="text-2xl font-bold mb-1">Live rides</h1>
      <p className="text-sm text-slate-500 mb-6">Auto-refreshes on every ride event.</p>
      {err && <p className="text-red-600 text-sm mb-4">{err}</p>}
      <div className="card !p-0 overflow-hidden">
        <div className="overflow-x-auto">
        <table className="w-full min-w-[640px]">
          <thead><tr><th className="th">Ride</th><th className="th">Status</th><th className="th">Cat / Mode</th><th className="th">Fare</th><th className="th">Flag</th><th className="th">Started</th></tr></thead>
          <tbody>
            {rides.map((r) => (
              <tr key={r.id}>
                <td className="td font-mono">{r.id.slice(0, 8)}</td>
                <td className="td"><span className={`badge ${STATUS_COLORS[r.status] ?? 'bg-slate-100 text-slate-600'}`}>{r.status}</span></td>
                <td className="td">{r.category} · {r.mode}</td>
                <td className="td">₹{r.fare_estimate_rs ?? '?'}</td>
                <td className="td">{r.suspicious
                  ? <span className="badge bg-red-100 text-red-700">⚠ {r.suspicious}</span>
                  : <span className="text-slate-400">—</span>}</td>
                <td className="td text-slate-500">{new Date(r.created_at).toLocaleString()}</td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
        {rides.length === 0 && <p className="p-5 text-sm text-slate-500">No live rides.</p>}
      </div>
    </AdminGate>
  );
}
