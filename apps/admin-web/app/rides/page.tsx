'use client';

import { useEffect, useState } from 'react';
import { supabaseAdmin } from '../lib/supabase';

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
  completed: 'bg-emerald-50 text-emerald-700',
  cancelled: 'bg-red-100 text-red-700',
};

export default function RidesPage() {
  const [rides, setRides] = useState<Ride[]>([]);
  const [err, setErr] = useState('');

  const load = async () => {
    try {
      const { data } = await supabaseAdmin.from('rides')
        .select('id,status,category,mode,fare_estimate_rs,suspicious,created_at')
        .in('status', ['requested', 'accepted', 'arrived', 'started', 'completed'])
        .order('created_at', { ascending: false }).limit(50);
      setRides((data ?? []) as Ride[]);
    } catch (_) {}
  };

  useEffect(() => { load(); }, []);

  return (
    <div className="space-y-6">
      <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center gap-4 mb-6">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Live Rides</h1>
          <p className="text-sm text-slate-500">Live ride events.</p>
        </div>
        <div className="flex items-center gap-2">
          <button className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-slate-600 rounded-lg border border-slate-200 hover:bg-slate-100">
            <span className="material-symbols-rounded text-sm">refresh</span>
            <span className="hidden sm:block">Refresh</span>
          </button>
        </div>
      </div>

      <div className="card p-0 overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="text-slate-400 border-b border-slate-100">
              <tr>
                <th className="px-4 py-3 font-medium">Ride</th>
                <th className="th px-4 py-3 text-left">Status</th>
                <th className="th px-4 py-3 text-left">Category / Mode</th>
                <th className="th px-4 py-3 font-medium">Fare</th>
                <th className="th px-4 py-3 text-left">Flag</th>
                <th className="th px-4 py-3 font-medium">Started</th>
              </tr>
            </thead>
            <tbody>
              {rides.map((r) => (
                <tr key={r.id} className="border-b border-slate-50 hover:bg-slate-50/50">
                  <td className="px-4 py-3 font-mono text-sm">{r.id.slice(0, 8)}</td>
                  <td className="px-4 py-3">
                    <span className={`badge ${STATUS_COLORS[r.status] ?? 'bg-slate-100 text-slate-600'}`}>
                      {r.status}
                    </span>
                  </td>
                  <td className="px-4 py-3">{r.category} · {r.mode}</td>
                  <td className="px-4 py-3 font-medium">₹{r.fare_estimate_rs ?? '?'}</td>
                  <td className="td px-4 py-3">
                    {r.suspicious
                      ? <span className="badge bg-red-100 text-red-700">{r.suspicious}</span>
                      : <span className="text-slate-400">—</span>
                    }
                  </td>
                  <td className="px-4 py-3 text-slate-500 text-sm">{new Date(r.created_at).toLocaleString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
          {rides.length === 0 && <p className="p-5 text-sm text-slate-500">No live rides.</p>}
        </div>
      </div>
    </div>
  );
}
