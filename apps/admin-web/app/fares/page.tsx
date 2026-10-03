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
    <main>
      <h1>Fare config — fare = max(min, base + per_km×km + per_min×min) × surge</h1>
      {err && <p style={{ color: 'red' }}>{err}</p>}
      {msg && <p style={{ color: 'green' }}>{msg}</p>}
      {rows.map((r) => (
        <div key={r.vehicle_category} style={{ border: '1px solid #ddd', padding: 12, margin: '8px 0', display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'end' }}>
          <b style={{ width: 60 }}>{r.vehicle_category}</b>
          {(['base_rs', 'per_km_rs', 'per_min_rs', 'min_fare_rs'] as const).map((k) => (
            <label key={k}>{k}<br />
              <input type="number" step="any" value={r[k]}
                onChange={(e) => setRows(rows.map((x) =>
                  x.vehicle_category === r.vehicle_category ? { ...x, [k]: +e.target.value } : x))}
                style={{ width: 90 }} />
            </label>
          ))}
          <button onClick={() => save(r)}>Save</button>
        </div>
      ))}
    </main>
    </AdminGate>
  );
}
