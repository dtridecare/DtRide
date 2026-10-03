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
      // Suspicious completions + post-start cancellations = refund candidates.
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
    else { setMsg(`Refunded 1 credit for ${id}`); load(); }
  };

  const resolve = async (id: string) => {
    setErr('');
    const { error } = await db().from('support_tickets').update({ status: 'resolved' }).eq('id', id);
    if (error) setErr(error.message);
    else load();
  };

  return (
    <AdminGate>
    <main>
      <h1 style={{ color: 'red' }}>SOS feed</h1>
      {sos.map((e) => (
        <div key={e.id} style={{ border: '2px solid red', padding: 12, margin: '8px 0' }}>
          <div><b>{new Date(e.created_at).toLocaleString()}</b> · user {e.user_id} · ride {e.ride_id ?? '—'}</div>
          <div>{e.note ?? 'No note'}</div>
        </div>
      ))}
      {sos.length === 0 && <p>No SOS events.</p>}

      <h1>Disputes — refund 1 credit</h1>
      {err && <p style={{ color: 'red' }}>{err}</p>}
      {msg && <p style={{ color: 'green' }}>{msg}</p>}
      {rides.map((r) => (
        <div key={r.id} style={{ border: '1px solid #ddd', padding: 12, margin: '8px 0' }}>
          <div><b>{r.id}</b> · {r.status} · {r.suspicious ?? 'no flag'} · driver {r.driver_id ?? '—'}</div>
          <button onClick={() => refund(r.id)}>Refund 1 credit</button>
        </div>
      ))}
      {rides.length === 0 && <p>No disputes.</p>}

      <h1>Support tickets</h1>
      {tickets.map((t) => (
        <div key={t.id} style={{ border: '1px solid #ddd', padding: 12, margin: '8px 0' }}>
          <div><b>{t.subject}</b> · {t.status} · ride {t.ride_id ?? '—'}</div>
          <div>{t.body ?? ''}</div>
          {t.status !== 'resolved' && <button onClick={() => resolve(t.id)}>Mark resolved</button>}
        </div>
      ))}
      {tickets.length === 0 && <p>No tickets.</p>}
    </main>
    </AdminGate>
  );
}
