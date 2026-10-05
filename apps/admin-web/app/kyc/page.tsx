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

type Detail = {
  profile: { full_name: string | null; phone: string | null } | null;
  vehicles: { category: string; make: string | null; model: string | null; plate: string }[];
  docs: { name: string; url: string }[];
};

type RiderRow = {
  id: string; full_name: string | null; phone: string | null;
  rider_kyc_status: string; rider_kyc_note: string | null;
};

export default function KycPage() {
  const [kind, setKind] = useState<'drivers' | 'riders'>('drivers');
  const [auto, setAuto] = useState(false);
  const [rows, setRows] = useState<Row[]>([]);
  const [riders, setRiders] = useState<RiderRow[]>([]);
  const [filter, setFilter] = useState<'pending' | 'approved' | 'rejected'>('pending');
  const [openId, setOpenId] = useState<string | null>(null);
  const [details, setDetails] = useState<Record<string, Detail>>({});
  const [note, setNote] = useState('');
  const [err, setErr] = useState('');

  const load = async () => {
    const { data, error } = await db().from('drivers').select('*').eq('kyc_status', filter).order('created_at', { ascending: false }).limit(50);
    if (error) setErr(error.message);
    else setRows((data ?? []) as Row[]);
  };
  const loadRiders = async () => {
    const { data, error } = await db().from('profiles')
      .select('id,full_name,phone,rider_kyc_status,rider_kyc_note')
      .eq('role', 'rider').neq('rider_kyc_status', 'not_submitted')
      .order('created_at', { ascending: false }).limit(50);
    if (error) setErr(error.message);
    else setRiders((data ?? []) as RiderRow[]);
  };
  useEffect(() => { setDetails({}); setOpenId(null); if (kind === 'drivers') load(); else loadRiders(); }, [filter, kind]);
  useEffect(() => {
    db().from('app_config').select('value').eq('key', 'rider_kyc_auto_approve').single()
      .then(({ data }) => setAuto(String(data?.value ?? 'false') === 'true'));
  }, []);

  const flipAuto = async () => {
    setErr('');
    const { error } = await db().from('app_config')
      .update({ value: (!auto).toString() }).eq('key', 'rider_kyc_auto_approve');
    if (error) setErr(error.message);
    else setAuto(!auto);
  };

  const toggle = async (id: string) => {
    if (openId === id) {
      setOpenId(null);
      return;
    }
    setOpenId(id);
    if (details[id]) return;
    const c = db();
    const [p, v, files] = await Promise.all([
      c.from('profiles').select('full_name,phone').eq('id', id).single(),
      c.from('vehicles').select('category,make,model,plate').eq('driver_id', id).order('created_at', { ascending: false }).limit(3),
      c.storage.from('kyc-docs').list(id, { limit: 20 }),
    ]);
    const docs: { name: string; url: string }[] = [];
    for (const f of files.data ?? []) {
      const { data } = await c.storage.from('kyc-docs').createSignedUrl(`${id}/${f.name}`, 3600);
      if (data) docs.push({ name: f.name, url: data.signedUrl });
    }
    setDetails((d) => ({
      ...d,
      [id]: {
        profile: (p.data ?? null) as Detail['profile'],
        vehicles: (v.data ?? []) as Detail['vehicles'],
        docs,
      },
    }));
  };

  const decide = async (id: string, approve: boolean) => {
    setErr('');
    const { error } = await db().rpc('decide_kyc', { p_driver: id, p_approve: approve, p_note: note || null });
    if (error) setErr(error.message);
    else load();
  };

  const decideRider = async (id: string, approve: boolean) => {
    setErr('');
    const { error } = await db().rpc('decide_rider_kyc', { p_user: id, p_approve: approve, p_note: note || null });
    if (error) setErr(error.message);
    else loadRiders();
  };

  return (
    <AdminGate>
      <h1 className="text-2xl font-bold mb-1">KYC approvals</h1>
      <div className="card flex flex-wrap items-center gap-3 mb-4">
        <div className="flex-1 min-w-52">
          <b>Rider auto-approve</b>
          <div className="text-sm text-slate-500">When on, rider KYC approves instantly without review.</div>
        </div>
        <button className={auto ? 'btn-primary !px-3 !py-1' : 'btn-outline !px-3 !py-1'} onClick={flipAuto}>
          {auto ? 'Automatic' : 'Manual'}
        </button>
      </div>
      <div className="flex gap-2 mb-4">
        {(['drivers', 'riders'] as const).map((k) => (
          <button key={k} onClick={() => setKind(k)}
            className={kind === k ? 'btn-primary !px-3 !py-1' : 'btn-outline !px-3 !py-1'}>
            {k[0].toUpperCase() + k.slice(1)}
          </button>
        ))}
      </div>
      {kind === 'drivers' && (
      <>
      <div className="flex gap-2 mb-4">
        {(['pending', 'approved', 'rejected'] as const).map((f) => (
          <button key={f} onClick={() => setFilter(f)}
            className={filter === f ? 'btn-primary !px-3 !py-1' : 'btn-outline !px-3 !py-1'}>
            {f[0].toUpperCase() + f.slice(1)}
          </button>
        ))}
      </div>
      <input className="input mb-4 w-full max-w-md" placeholder="Decision note (optional, e.g. rejection reason)"
        value={note} onChange={(e) => setNote(e.target.value)} />
      {err && <p className="text-red-600 text-sm mb-4">{err}</p>}
      <div className="grid gap-3">
        {rows.map((r) => {
          const d = details[r.id];
          return (
            <div key={r.id} className="card">
              <div className="flex flex-wrap items-center gap-4">
                <div className="flex-1 min-w-52">
                  <div className="font-semibold">{d?.profile?.full_name ?? <span className="text-slate-400">Unnamed driver</span>}</div>
                  <div className="text-sm text-slate-500">
                    {d?.profile?.phone ?? ''} {r.vehicle_category} · UPI {r.upi_id ?? '—'} · strikes {r.strikes}
                  </div>
                  <div className="font-mono text-xs text-slate-400">{r.id.slice(0, 8)}</div>
                  {r.kyc_status === 'rejected' && r.kyc_notes && (
                    <div className="text-sm text-red-600 mt-1">Note: {r.kyc_notes}</div>
                  )}
                </div>
                <button className="btn-outline !px-3 !py-1" onClick={() => toggle(r.id)}>
                  {openId === r.id ? 'Hide' : 'Details'}
                </button>
                {r.kyc_status === 'pending' && (
                  <>
                    <button className="btn-primary" onClick={() => decide(r.id, true)}>Approve</button>
                    <button className="btn-outline" onClick={() => decide(r.id, false)}>Reject</button>
                  </>
                )}
              </div>
              {openId === r.id && (
                <div className="mt-4 pt-4 border-t border-slate-100 text-sm">
                  {!d ? <p className="text-slate-500">Loading…</p> : (
                    <>
                      <div className="font-semibold mb-1">Vehicles</div>
                      {d.vehicles.length === 0 && <p className="text-slate-500 mb-2">None registered.</p>}
                      {d.vehicles.map((veh, i) => (
                        <p key={i} className="text-slate-600">
                          {veh.category} · {veh.make ?? ''} {veh.model ?? ''} · <b>{veh.plate}</b>
                        </p>
                      ))}
                      <div className="font-semibold mt-3 mb-2">Uploaded documents ({d.docs.length})</div>
                      {d.docs.length === 0 && <p className="text-slate-500">No files uploaded.</p>}
                      <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                        {d.docs.map((doc) => (
                          <a key={doc.name} href={doc.url} target="_blank" rel="noreferrer"
                            className="block rounded-lg overflow-hidden border border-slate-200 hover:border-indigo-400">
                            {/* eslint-disable-next-line @next/next/no-img-element */}
                            <img src={doc.url} alt={doc.name} className="h-28 w-full object-cover" />
                            <div className="px-2 py-1 text-xs truncate text-slate-600">{doc.name}</div>
                          </a>
                        ))}
                      </div>
                    </>
                  )}
                </div>
              )}
            </div>
          );
        })}
        {rows.length === 0 && <div className="card text-sm text-slate-500">Nothing here.</div>}
      </div>
      </>
      )}
      {kind === 'riders' && (
      <div className="grid gap-3">
        {riders.map((r) => {
          const d = details[r.id];
          return (
            <div key={r.id} className="card">
              <div className="flex flex-wrap items-center gap-4">
                <div className="flex-1 min-w-52">
                  <div className="font-semibold">{d?.profile?.full_name ?? r.full_name ?? <span className="text-slate-400">Unnamed rider</span>}</div>
                  <div className="text-sm text-slate-500">
                    {d?.profile?.phone ?? r.phone ?? ''} · <span className="badge bg-amber-100 text-amber-700">{r.rider_kyc_status}</span>
                  </div>
                  <div className="font-mono text-xs text-slate-400">{r.id.slice(0, 8)}</div>
                  {r.rider_kyc_status === 'rejected' && r.rider_kyc_note && (
                    <div className="text-sm text-red-600 mt-1">Note: {r.rider_kyc_note}</div>
                  )}
                </div>
                <button className="btn-outline !px-3 !py-1" onClick={() => toggle(r.id)}>
                  {openId === r.id ? 'Hide' : 'Details'}
                </button>
                {r.rider_kyc_status === 'pending' && (
                  <>
                    <button className="btn-primary" onClick={() => decideRider(r.id, true)}>Approve</button>
                    <button className="btn-outline" onClick={() => decideRider(r.id, false)}>Reject</button>
                  </>
                )}
              </div>
              {openId === r.id && (
                <div className="mt-4 pt-4 border-t border-slate-100 text-sm">
                  {!d ? <p className="text-slate-500">Loading…</p> : (
                    <>
                      <div className="font-semibold mt-3 mb-2">Uploaded documents ({d.docs.length})</div>
                      {d.docs.length === 0 && <p className="text-slate-500">No files uploaded.</p>}
                      <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                        {d.docs.map((doc) => (
                          <a key={doc.name} href={doc.url} target="_blank" rel="noreferrer"
                            className="block rounded-lg overflow-hidden border border-slate-200 hover:border-indigo-400">
                            {/* eslint-disable-next-line @next/next/no-img-element */}
                            <img src={doc.url} alt={doc.name} className="h-28 w-full object-cover" />
                            <div className="px-2 py-1 text-xs truncate text-slate-600">{doc.name}</div>
                          </a>
                        ))}
                      </div>
                    </>
                  )}
                </div>
              )}
            </div>
          );
        })}
        {riders.length === 0 && <div className="card text-sm text-slate-500">No rider KYC submissions.</div>}
      </div>
      )}
    </AdminGate>
  );
}
