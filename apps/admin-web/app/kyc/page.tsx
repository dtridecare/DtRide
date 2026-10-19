'use client';

import { useEffect, useState } from 'react';
import { supabaseAdmin } from '../lib/supabase';

type Row = {
  id: string; kyc_status: string; vehicle_category: string;
  upi_id: string | null; strikes: number; kyc_notes: string | null;
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
  const [details, setDetails] = useState<Record<string, any>>({});
  const [note, setNote] = useState('');
  const [err, setErr] = useState('');
  const [loading, setLoading] = useState(false);

  const load = async () => {
    try {
      const { data, error } = await supabaseAdmin.from('drivers').select('*').eq('kyc_status', filter).order('created_at', { ascending: false }).limit(50);
      if (error) setErr(error.message);
      else setRows((data ?? []) as Row[]);
    } catch (_) {}
  };

  const loadRiders = async () => {
    try {
      const { data, error } = await supabaseAdmin.from('profiles')
        .select('id,full_name,phone,rider_kyc_status,rider_kyc_note')
        .eq('role', 'rider').neq('rider_kyc_status', 'not_submitted')
        .order('created_at', { ascending: false }).limit(50);
      if (error) setErr(error.message);
      else setRiders((data ?? []) as RiderRow[]);
    } catch (_) {}
  };

  const loadAuto = async () => {
    try {
      const { data } = await supabaseAdmin.from('app_config').select('value').eq('key', 'rider_kyc_auto_approve').single();
      setAuto(String(data?.value ?? 'false') === 'true');
    } catch (_) {}
  };

  useEffect(() => {
    setDetails({}); setOpenId(null);
    if (kind === 'drivers') load(); else loadRiders();
  }, [filter, kind]);

  useEffect(() => { loadAuto(); }, []);

  const flipAuto = async () => {
    setErr('');
    try {
      const { error } = await supabaseAdmin.from('app_config').update({ value: (!auto).toString() }).eq('key', 'rider_kyc_auto_approve');
      if (error) setErr(error.message);
      else setAuto(!auto);
    } catch (_) {}
  };

  const toggle = async (id: string) => {
    if (openId === id) { setOpenId(null); return; }
    setOpenId(id);
    if (details[id]) return;
    try {
      const [p, v, files] = await Promise.all([
        supabaseAdmin.from('profiles').select('full_name,phone').eq('id', id).single(),
        supabaseAdmin.from('vehicles').select('category,make,model,plate').eq('driver_id', id).order('created_at', { ascending: false }).limit(3),
        supabaseAdmin.storage.from('kyc-docs').list(id, { limit: 20 }),
      ]);
      const docs: { name: string; url: string }[] = [];
      for (const f of files.data ?? []) {
        const { data } = await supabaseAdmin.storage.from('kyc-docs').createSignedUrl(`${id}/${f.name}`, 3600);
        if (data) docs.push({ name: f.name, url: data.signedUrl });
      }
      setDetails((d: any) => ({
        ...d,
        [id]: {
          profile: (p.data ?? null),
          vehicles: (v.data ?? []),
          docs,
        },
      }));
    } catch (_) {}
  };

  const decide = async (id: string, approve: boolean) => {
    setErr('');
    try {
      const { error } = await supabaseAdmin.rpc('decide_kyc', { p_driver: id, p_approve: approve, p_note: note || null });
      if (error) setErr(error.message);
      else { load(); setOpenId(null); }
    } catch (_) {}
  };

  const decideRider = async (id: string, approve: boolean) => {
    setErr('');
    try {
      const { error } = await supabaseAdmin.rpc('decide_rider_kyc', { p_user: id, p_approve: approve, p_note: note || null });
      if (error) setErr(error.message);
      else { loadRiders(); setOpenId(null); }
    } catch (_) {}
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center gap-4 mb-6">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">KYC Approvals</h1>
          <p className="text-sm text-slate-500">Review and approve driver and rider KYC documents.</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={flipAuto}
            className={`px-3 py-2 text-sm font-medium rounded-lg transition-colors ${auto ? 'bg-emerald-500 text-white' : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'}`}
          >
            {auto ? 'Auto-approve: ON' : 'Auto-approve: OFF'}
          </button>
        </div>
      </div>

      <div className="flex gap-2 mb-4">
        {(['drivers', 'riders'] as const).map((k) => (
          <button key={k} onClick={() => setKind(k)}
            className={kind === k ? 'px-3 py-2 text-sm font-medium bg-blue-600 text-white rounded-lg' : 'px-3 py-2 text-sm font-medium rounded-lg border border-slate-200 text-slate-600 hover:bg-slate-50'}>
            {k[0].toUpperCase() + k.slice(1)}
          </button>
        ))}
      </div>

      {kind === 'drivers' && (
        <>
          <div className="flex gap-2 mb-4">
            {(['pending', 'approved', 'rejected'] as const).map((f) => (
              <button key={f} onClick={() => setFilter(f)}
                className={filter === f ? 'px-3 py-2 text-sm font-medium bg-blue-600 text-white rounded-lg' : 'px-3 py-2 text-sm font-medium rounded-lg border border-slate-200 text-slate-600 hover:bg-slate-50'}>
                {f[0].toUpperCase() + f.slice(1)}
              </button>
            ))}
          </div>
          <input className="mb-4 w-full max-w-md border border-slate-200 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent" placeholder="Decision note (optional)" value={note} onChange={(e) => setNote(e.target.value)} />
          {err && <p className="text-red-600 text-sm mb-4">{err}</p>}
          <div className="grid gap-3">
            {rows.map((r) => {
              const d = details[r.id];
              return (
                <div key={r.id} className="card p-6">
                  <div className="flex flex-wrap items-center gap-4">
                    <div className="flex-1 min-w-52">
                      <div className="font-semibold">{d?.profile?.full_name ?? 'Unnamed driver'}</div>
                      <div className="text-sm text-slate-500">
                        {d?.profile?.phone ?? ''} {r.vehicle_category} · UPI {r.upi_id ?? '—'} · Strikes {r.strikes}
                      </div>
                      <div className="font-mono text-xs text-slate-400">{r.id.slice(0, 8)}</div>
                      {r.kyc_status === 'rejected' && r.kyc_notes && (
                        <div className="text-sm text-red-600 mt-1">Note: {r.kyc_notes}</div>
                      )}
                    </div>
                    <button className="px-2 py-1 text-xs rounded border border-slate-200 hover:bg-slate-100" onClick={() => toggle(r.id)}>
                      {openId === r.id ? 'Hide' : 'Details'}
                    </button>
                    {r.kyc_status === 'pending' && (
                      <>
                        <button className="px-3 py-1 text-xs font-medium bg-emerald-500 text-white rounded-lg hover:bg-emerald-600" onClick={() => decide(r.id, true)}>Approve</button>
                        <button className="px-3 py-1 text-xs font-medium bg-red-50 text-red-700 rounded-lg border border-red-200 hover:bg-red-50 hover:text-red-700" onClick={() => decide(r.id, false)}>Reject</button>
                      </>
                    )}
                  </div>
                  {openId === r.id && (
                    <div className="mt-4 pt-4 border-t border-slate-100 text-sm">
                      {!d ? <p className="text-slate-500">Loading…</p> : (
                        <>
                          <div className="font-semibold mb-1">Vehicles</div>
                          {d.vehicles.length === 0 && <p className="text-slate-500 mb-2">None registered.</p>}
                          {d.vehicles.map((veh: any, i: number) => (
                            <p key={i} className="text-slate-600">{veh.category} · {veh.make ?? ''} {veh.model ?? ''} · <b>{veh.plate}</b></p>
                          ))}
                          <div className="font-semibold mt-3 mb-2">Uploaded Documents ({d.docs.length})</div>
                          {d.docs.length === 0 && <p className="text-slate-500">No files uploaded.</p>}
                          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                            {d.docs.map((doc: any) => (
                              <a key={doc.name} href={doc.url} target="_blank" rel="noreferrer"
                                className="block rounded-lg overflow-hidden border border-slate-200 hover:border-indigo-400">
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
            {rows.length === 0 && <div className="card p-6 text-sm text-slate-500">Nothing here.</div>}
          </div>
        </>
      )}
      {kind === 'riders' && (
        <div className="grid gap-3">
          {riders.map((r) => {
            const d = details[r.id];
            return (
              <div key={r.id} className="card p-6">
                <div className="flex flex-wrap items-center gap-4">
                  <div className="flex-1 min-w-52">
                    <div className="font-semibold">{d?.profile?.full_name ?? r.full_name ?? 'Unnamed rider'}</div>
                    <div className="text-sm text-slate-500">{d?.profile?.phone ?? r.phone ?? ''} · <span className={`badge ${r.rider_kyc_status === 'approved' ? 'bg-emerald-100 text-emerald-700' : d.kyc_status === 'rejected' ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-700'}`}>{r.rider_kyc_status}</span></div>
                    <div className="font-mono text-xs text-slate-400">{r.id.slice(0, 8)}</div>
                    {r.rider_kyc_status === 'rejected' && r.rider_kyc_note && (
                      <div className="text-sm text-red-600 mt-1">Note: {r.rider_kyc_note}</div>
                    )}
                  </div>
                  <button className="px-2 py-1 text-xs rounded border border-slate-200 hover:bg-slate-100" onClick={() => toggle(r.id)}>
                    {openId === r.id ? 'Hide' : 'Details'}
                  </button>
                  {r.rider_kyc_status === 'pending' && (
                    <>
                      <button className="px-3 py-1 text-xs font-medium bg-emerald-500 text-white rounded-lg hover:bg-emerald-600" onClick={() => decideRider(r.id, true)}>Approve</button>
                      <button className="px-3 py-1 text-xs font-medium bg-red-50 text-red-700 rounded-lg border border-red-200 hover:bg-red-50 hover:text-red-700" onClick={() => decideRider(r.id, false)}>Reject</button>
                    </>
                  )}
                </div>
                {openId === r.id && (
                  <div className="mt-4 pt-4 border-t border-slate-100 text-sm">
                    {!d ? <p className="text-slate-500">Loading…</p> : (
                      <>
                        <div className="font-semibold mt-3 mb-2">Uploaded Documents ({d.docs.length})</div>
                        {d.docs.length === 0 && <p className="text-slate-500">No files uploaded.</p>}
                        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                          {d.docs.map((doc: any) => (
                            <a key={doc.name} href={doc.url} target="_blank" rel="noreferrer" className="block rounded-lg overflow-hidden border border-slate-200 hover:border-indigo-400">
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
          {riders.length === 0 && <div className="card p-6 text-sm text-slate-500">No rider KYC submissions.</div>}
        </div>
      )}
    </div>
  );
}
