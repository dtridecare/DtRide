'use client';

import { useEffect, useState } from 'react';
import { supabaseAdmin } from '../lib/supabase';

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
    try {
      const { data } = await supabaseAdmin.from('coupons').select('*').order('created_at', { ascending: false });
      setRows((data ?? []) as Coupon[]);
    } catch (_) {}
  };

  useEffect(() => { load(); }, []);

  const create = async () => {
    setErr('');
    try {
      const { error } = await supabaseAdmin.from('coupons').insert({
        code: code.trim().toUpperCase(), discount_rs: discount, max_uses: maxUses,
      });
      if (error) setErr(error.message);
      else { setCode(''); load(); }
    } catch (_) {}
  };

  const toggle = async (c: Coupon) => {
    try {
      const { error } = await supabaseAdmin.from('coupons').update({ is_active: !c.is_active }).eq('id', c.id);
      if (error) setErr(error.message);
      else load();
    } catch (_) {}
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center gap-4 mb-6">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Coupons</h1>
          <p className="text-sm text-slate-500">Platform-funded rider discounts.</p>
        </div>
        <div className="flex items-center gap-2">
          <button className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-slate-600 rounded-lg border border-slate-200 hover:bg-slate-100">
            <span className="material-symbols-rounded text-sm">refresh</span>
            <span className="hidden sm:block">Refresh</span>
          </button>
        </div>
      </div>

      <div className="grid gap-2">
        {rows.map((c) => (
          <div key={c.id} className="card p-4 flex items-center justify-between gap-4">
            <div className="flex-1">
              <div className="flex items-center gap-2 font-medium text-slate-900">
                <span className="font-mono">{c.code}</span>
                <span className="text-sm text-slate-500">−₹{c.discount_rs}</span>
              </div>
              <div className="text-sm text-slate-500">
                Used {c.used_count}{c.max_uses !== null ? ` / ${c.max_uses}` : ''}
              </div>
            </div>
            <span className={`badge ${c.is_active ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-200 text-slate-600'}`}>
              {c.is_active ? 'Active' : 'Disabled'}
            </span>
            <button
              className="px-2 py-1 text-xs rounded border border-slate-200 hover:bg-slate-100"
              onClick={() => toggle(c)}
            >
              {c.is_active ? 'Disable' : 'Enable'}
            </button>
          </div>
        ))}
        {rows.length === 0 && <div className="card p-6 text-sm text-slate-500">No coupons yet.</div>}
      </div>

      <div className="card p-6">
        <div className="flex flex-wrap gap-2 mb-2">
          <div className="flex-1 min-w-[200px]">
            <h3 className="text-sm font-semibold text-slate-700 mb-2">New coupon</h3>
          </div>
          <input type="text" placeholder="CODE"
            className="border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            value={code} onChange={(e) => setCode(e.target.value)} />
          <input type="number" placeholder="₹ off"
            className="border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent w-32"
            value={discount} onChange={(e) => setDiscount(+e.target.value)} />
          <input type="number" placeholder="Max uses"
            className="border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent w-32"
            value={maxUses} onChange={(e) => setMaxUses(+e.target.value)} />
          <button className="bg-blue-600 text-white px-4 py-2 text-sm font-medium rounded-lg hover:bg-blue-700"
            onClick={create}>Create</button>
        </div>
      </div>
    </div>
  );
}
