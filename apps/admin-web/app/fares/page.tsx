'use client';

import { useEffect, useState } from 'react';
import { supabaseAdmin } from '../lib/supabase';

type Fare = {
  vehicle_category: string;
  base_rs: number;
  per_km_rs: number;
  per_min_rs: number;
  min_fare_rs: number;
};

export default function FaresPage() {
  const [rows, setRows] = useState<Fare[]>([]);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    try {
      const { data } = await supabaseAdmin.from('fare_config').select('*').order('base_rs');
      setRows((data ?? []) as Fare[]);
    } catch (_) {}
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const save = async (r: Fare) => {
    try {
      await supabaseAdmin.from('fare_config').update({
        base_rs: r.base_rs,
        per_km_rs: r.per_km_rs,
        per_min_rs: r.per_min_rs,
        min_fare_rs: r.min_fare_rs,
      }).eq('vehicle_category', r.vehicle_category);
      await load();
    } catch (_) {}
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center gap-4 mb-6">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Fare Config</h1>
          <p className="text-sm text-slate-500">fare = max(min, base + per_km × km + per_min × min) × surge</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        {rows.map((r) => (
          <div key={r.vehicle_category} className="card p-6">
            <div className="flex items-start justify-between mb-4">
              <span className="text-sm font-medium text-slate-700">{r.vehicle_category}</span>
            </div>
            <div className="space-y-2">
              <div className="flex items-center gap-3">
                <label className="text-xs text-slate-500 min-w-[64px]">Base ₹</label>
                <input type="number" step="any"
                  className="border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  value={r.base_rs}
                  onChange={(e) => setRows(rows.map(x => x.vehicle_category === r.vehicle_category ? { ...x, base_rs: +e.target.value } : x))}
                />
              </div>
              <div className="flex items-center gap-3">
                <label className="text-xs text-slate-500 min-w-[64px]">Per km ₹</label>
                <input type="number" step="any"
                  className="border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  value={r.per_km_rs}
                  onChange={(e) => setRows(rows.map(x => x.vehicle_category === r.vehicle_category ? { ...x, per_km_rs: +e.target.value } : x))}
                />
              </div>
              <div className="flex items-center gap-3">
                <label className="text-xs text-slate-500 min-w-[64px]">Per min ₹</label>
                <input type="number" step="any"
                  className="border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  value={r.per_min_rs}
                  onChange={(e) => setRows(rows.map(x => x.vehicle_category === r.vehicle_category ? { ...x, per_min_rs: +e.target.value } : x))}
                />
              </div>
              <div className="flex items-center gap-3">
                <label className="text-xs text-slate-500 min-w-[64px]">Min fare ₹</label>
                <input type="number" step="any"
                  className="border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                  value={r.min_fare_rs}
                  onChange={(e) => setRows(rows.map(x => x.vehicle_category === r.vehicle_category ? { ...x, min_fare_rs: +e.target.value } : x))}
                />
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
