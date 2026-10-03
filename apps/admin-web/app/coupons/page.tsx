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
    <main>
      <h1>Coupons — platform-funded rider discounts</h1>
      {err && <p style={{ color: 'red' }}>{err}</p>}
      {rows.map((c) => (
        <div key={c.id} style={{ border: '1px solid #ddd', padding: 12, margin: '8px 0' }}>
          <b>{c.code}</b> · −₹{c.discount_rs} · used {c.used_count}/{c.max_uses ?? '∞'} ·{' '}
          {c.is_active ? 'active' : 'disabled'}{' '}
          <button onClick={() => toggle(c)}>{c.is_active ? 'Disable' : 'Enable'}</button>
        </div>
      ))}
      <h2>New coupon</h2>
      <div style={{ display: 'flex', gap: 8 }}>
        <input placeholder="CODE" value={code} onChange={(e) => setCode(e.target.value)} />
        <input type="number" placeholder="₹ off" value={discount} onChange={(e) => setDiscount(+e.target.value)} />
        <input type="number" placeholder="Max uses" value={maxUses} onChange={(e) => setMaxUses(+e.target.value)} />
        <button onClick={create}>Create</button>
      </div>
    </main>
    </AdminGate>
  );
}
