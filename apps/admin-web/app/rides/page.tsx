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
    <main>
      <h1>Live rides</h1>
      {err && <p style={{ color: 'red' }}>{err}</p>}
      {rides.map((r) => (
        <div key={r.id} style={{ border: '1px solid #ddd', padding: 12, margin: '8px 0' }}>
          <div><b>{r.id.slice(0, 8)}</b> · {r.status} · {r.category} · {r.mode} · ₹{r.fare_estimate_rs ?? '?'}{' '}
            {r.suspicious && <span style={{ color: 'red' }}>⚠ {r.suspicious}</span>}</div>
          <small>{new Date(r.created_at).toLocaleString()}</small>
        </div>
      ))}
      {rides.length === 0 && <p>No live rides.</p>}
    </main>
    </AdminGate>
  );
}
