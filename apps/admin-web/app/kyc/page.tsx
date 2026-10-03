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
      <h1 className="text-2xl font-bold mb-1">KYC approvals</h1>
      <p className="text-sm text-slate-500 mb-6">{rows.length} driver(s) waiting.</p>
      <input className="input mb-4 w-full max-w-md" placeholder="Decision note (optional)"
        value={note} onChange={(e) => setNote(e.target.value)} />
      {err && <p className="text-red-600 text-sm mb-4">{err}</p>}
      <div className="grid gap-3">
        {rows.map((r) => (
          <div key={r.id} className="card flex flex-wrap items-center gap-4">
            <div className="flex-1 min-w-52">
              <div className="font-mono text-sm">{r.id}</div>
              <div className="text-sm text-slate-500">
                {r.vehicle_category} · UPI {r.upi_id ?? '—'} · strikes {r.strikes}
              </div>
            </div>
            <button className="btn-primary" onClick={() => decide(r.id, true)}>Approve</button>
            <button className="btn-outline" onClick={() => decide(r.id, false)}>Reject</button>
          </div>
        ))}
        {rows.length === 0 && <div className="card text-sm text-slate-500">No pending KYC.</div>}
      </div>
    </AdminGate>
  );
}
