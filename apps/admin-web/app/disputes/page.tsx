'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
import AdminGate from '../../lib/AdminGate';

const db = () =>
  createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);

type Ride = { id: string; status: string; suspicious: string | null; driver_id: string | null };
type Sos = { id: string; ride_id: string | null; user_id: string; note: string | null; created_at: string };
type Ticket = { id: string; ride_id: string | null; subject: string; body: string | null; status: string; created_at: string };

export default function DisputesPage() {
  const [rides, setRides] = useState<Ride[]>([]);
  const [sos, setSos] = useState<Sos[]>([]);
  const [tickets, setTickets] = useState<Ticket[]>([]);
  const [err, setErr] = useState('');
  const [msg, setMsg] = useState('');

  const load = async () => {
    const c = db();
    const [r, s, t] = await Promise.all([
      c.from('rides').select('id,status,suspicious,driver_id')
        .or('suspicious.not.is.null,status.eq.cancelled_after_start')
        .order('created_at', { ascending: false }).limit(50),
      c.from('sos_events').select('*').order('created_at', { ascending: false }).limit(20),
      c.from('support_tickets').select('*').order('created_at', { ascending: false }).limit(50),
    ]);
    if (r.error) setErr(r.error.message);
    else setRides((r.data ?? []) as Ride[]);
    if (!s.error) setSos((s.data ?? []) as Sos[]);
    if (!t.error) setTickets((t.data ?? []) as Ticket[]);
  };
  useEffect(() => { load(); }, []);

  const refund = async (id: string) => {
    setErr(''); setMsg('');
    const { error } = await db().rpc('refund_ride_credit', { p_ride: id, p_note: 'admin_refund' });
    if (error) setErr(error.message);
    else { setMsg(`Refunded 1 credit for ${id.slice(0, 8)}`); load(); }
  };

  const resolve = async (id: string) => {
    setErr('');
    const { error } = await db().from('support_tickets').update({ status: 'resolved' }).eq('id', id);
    if (error) setErr(error.message);
    else load();
  };

  return (
    <AdminGate>
      <h1 className="text-2xl font-bold mb-6">Disputes & safety</h1>
      {err && <p className="text-red-600 text-sm mb-4">{err}</p>}
      {msg && <p className="text-emerald-600 text-sm mb-4">{msg}</p>}

      <h2 className="font-semibold text-red-700 mb-2">🚨 SOS feed</h2>
      <div className="grid gap-2 mb-8">
        {sos.map((e) => (
          <div key={e.id} className="rounded-xl border-2 border-red-300 bg-red-50 p-4 text-sm">
            <b>{new Date(e.created_at).toLocaleString()}</b> · user <span className="font-mono">{e.user_id.slice(0, 8)}</span> · ride {e.ride_id?.slice(0, 8) ?? '—'}
            <div>{e.note ?? 'No note'}</div>
          </div>
        ))}
        {sos.length === 0 && <div className="card text-sm text-slate-500">No SOS events.</div>}
      </div>

      <h2 className="font-semibold mb-2">Refund candidates</h2>
      <div className="grid gap-2 mb-8">
        {rides.map((r) => (
          <div key={r.id} className="card flex flex-wrap items-center gap-3">
            <span className="font-mono text-sm">{r.id.slice(0, 8)}</span>
            <span className="badge bg-slate-100 text-slate-700">{r.status}</span>
            <span className="text-sm text-slate-500">{r.suspicious ?? 'no flag'}</span>
            <button className="btn-primary ml-auto" onClick={() => refund(r.id)}>Refund 1 credit</button>
          </div>
        ))}
        {rides.length === 0 && <div className="card text-sm text-slate-500">No disputes.</div>}
      </div>

      <h2 className="font-semibold mb-2">Support tickets</h2>
      <div className="grid gap-2">
        {tickets.map((t) => (
          <div key={t.id} className="card">
            <div className="flex flex-wrap items-center gap-2">
              <b>{t.subject}</b>
              <span className={`badge ${t.status === 'resolved' ? 'bg-emerald-100 text-emerald-700' : 'bg-amber-100 text-amber-700'}`}>{t.status}</span>
              {t.status !== 'resolved' && <button className="btn-outline !px-3 !py-1 ml-auto" onClick={() => resolve(t.id)}>Mark resolved</button>}
            </div>
            <div className="text-sm text-slate-500 mt-1">{t.body ?? ''}</div>
          </div>
        ))}
        {tickets.length === 0 && <div className="card text-sm text-slate-500">No tickets.</div>}
      </div>
    </AdminGate>
  );
}
