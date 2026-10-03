'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
import AdminGate from '../../lib/AdminGate';

const db = () =>
  createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);

type Fare = {
  vehicle_category: string; base_rs: number;
  per_km_rs: number; per_min_rs: number; min_fare_rs: number;
};

const FIELDS = [
  { k: 'base_rs', label: 'Base ₹' },
  { k: 'per_km_rs', label: 'Per km ₹' },
  { k: 'per_min_rs', label: 'Per min ₹' },
  { k: 'min_fare_rs', label: 'Min fare ₹' },
] as const;

export default function FaresPage() {
  const [rows, setRows] = useState<Fare[]>([]);
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');

  const load = async () => {
    const { data, error } = await db().from('fare_config').select('*').order('base_rs');
    if (error) setErr(error.message);
    else setRows((data ?? []) as Fare[]);
  };
  useEffect(() => { load(); }, []);

  const save = async (r: Fare) => {
    setErr(''); setMsg('');
    const { error } = await db().from('fare_config').update({
      base_rs: r.base_rs, per_km_rs: r.per_km_rs,
      per_min_rs: r.per_min_rs, min_fare_rs: r.min_fare_rs,
    }).eq('vehicle_category', r.vehicle_category);
    if (error) setErr(error.message);
    else { setMsg(`Saved ${r.vehicle_category}`); load(); }
  };

  return (
    <AdminGate>
      <h1 className="text-2xl font-bold mb-1">Fare config</h1>
      <p className="text-sm text-slate-500 mb-6">fare = max(min, base + per_km × km + per_min × min) × surge</p>
      {err && <p className="text-red-600 text-sm mb-4">{err}</p>}
      {msg && <p className="text-emerald-600 text-sm mb-4">{msg}</p>}
      <div className="grid gap-3">
        {rows.map((r) => (
          <div key={r.vehicle_category} className="card flex flex-wrap items-end gap-3">
            <b className="w-16">{r.vehicle_category}</b>
            {FIELDS.map((f) => (
              <label key={f.k} className="text-xs text-slate-500">{f.label}<br />
                <input className="input w-24" type="number" step="any" value={r[f.k]}
                  onChange={(e) => setRows(rows.map((x) =>
                    x.vehicle_category === r.vehicle_category ? { ...x, [f.k]: +e.target.value } : x))} />
              </label>
            ))}
            <button className="btn-primary" onClick={() => save(r)}>Save</button>
          </div>
        ))}
      </div>
    </AdminGate>
  );
}
