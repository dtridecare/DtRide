'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
import AdminGate from '../../lib/AdminGate';

const db = () =>
  createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);

type Coupon = {
  id: string; code: string; discount_rs: number;
  max_uses: number | null; used_count: number;
  valid_to: string | null; is_active: boolean;
};

export default function CouponsPage() {
  const [rows, setRows] = useState<Coupon[]>([]);
  const [code, setCode] = useState('');
  const [discount, setDiscount] = useState(50);
  const [maxUses, setMaxUses] = useState(1000);
  const [err, setErr] = useState('');

  const load = async () => {
    const { data, error } = await db().from('coupons').select('*').order('created_at', { ascending: false });
    if (error) setErr(error.message);
    else setRows((data ?? []) as Coupon[]);
  };
  useEffect(() => { load(); }, []);

  const create = async () => {
    setErr('');
    const { error } = await db().from('coupons').insert({
      code: code.trim().toUpperCase(), discount_rs: discount, max_uses: maxUses,
    });
    if (error) setErr(error.message);
    else { setCode(''); load(); }
  };

  const toggle = async (c: Coupon) => {
    const { error } = await db().from('coupons').update({ is_active: !c.is_active }).eq('id', c.id);
    if (error) setErr(error.message);
    else load();
  };

  return (
    <AdminGate>
      <h1 className="text-2xl font-bold mb-1">Coupons</h1>
      <p className="text-sm text-slate-500 mb-6">Platform-funded rider discounts.</p>
      {err && <p className="text-red-600 text-sm mb-4">{err}</p>}
      <div className="grid gap-2 mb-6">
        {rows.map((c) => (
          <div key={c.id} className="card flex flex-wrap items-center gap-3">
            <b className="font-mono">{c.code}</b>
            <span className="text-sm">−₹{c.discount_rs} · used {c.used_count}/{c.max_uses ?? '∞'}</span>
            <span className={`badge ${c.is_active ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-200 text-slate-600'}`}>
              {c.is_active ? 'active' : 'disabled'}
            </span>
            <button className="btn-outline !px-3 !py-1 ml-auto" onClick={() => toggle(c)}>{c.is_active ? 'Disable' : 'Enable'}</button>
          </div>
        ))}
      </div>
      <div className="card">
        <div className="font-semibold mb-3">New coupon</div>
        <div className="flex flex-wrap gap-2">
          <input className="input" placeholder="CODE" value={code} onChange={(e) => setCode(e.target.value)} />
          <input className="input w-28" type="number" placeholder="₹ off" value={discount} onChange={(e) => setDiscount(+e.target.value)} />
          <input className="input w-32" type="number" placeholder="Max uses" value={maxUses} onChange={(e) => setMaxUses(+e.target.value)} />
          <button className="btn-primary" onClick={create}>Create</button>
        </div>
      </div>
    </AdminGate>
  );
}
