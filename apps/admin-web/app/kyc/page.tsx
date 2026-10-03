'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
import AdminGate from '../../lib/AdminGate';

const db = () =>
  createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);

type Row = {
  id: string; kyc_status: string; vehicle_category: string;
  upi_id: string | null; strikes: number; kyc_notes: string | null;
};

export default function KycPage() {
  const [rows, setRows] = useState<Row[]>([]);
  const [note, setNote] = useState('');
  const [err, setErr] = useState('');

  const load = async () => {
    const { data, error } = await db().from('drivers').select('*').eq('kyc_status', 'pending');
    if (error) setErr(error.message);
    else setRows((data ?? []) as Row[]);
  };
  useEffect(() => { load(); }, []);

  const decide = async (id: string, approve: boolean) => {
    setErr('');
    const { error } = await db().rpc('decide_kyc', { p_driver: id, p_approve: approve, p_note: note || null });
    if (error) setErr(error.message);
    else load();
  };

  return (
    <AdminGate>
    <main>
      <h1>KYC approvals</h1>
      <input placeholder="Note (optional)" value={note} onChange={(e) => setNote(e.target.value)} style={{ width: 320 }} />
      {err && <p style={{ color: 'red' }}>{err}</p>}
      {rows.map((r) => (
        <div key={r.id} style={{ border: '1px solid #ddd', padding: 12, margin: '8px 0' }}>
          <div><b>{r.id}</b> · {r.vehicle_category} · UPI {r.upi_id ?? '—'} · strikes {r.strikes}</div>
          <button onClick={() => decide(r.id, true)}>Approve</button>{' '}
          <button onClick={() => decide(r.id, false)}>Reject</button>
        </div>
      ))}
      {rows.length === 0 && <p>No pending KYC.</p>}
    </main>
    </AdminGate>
  );
}
