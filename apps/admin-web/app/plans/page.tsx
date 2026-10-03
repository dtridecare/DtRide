'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
import AdminGate from '../../lib/AdminGate';

const db = () =>
  createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);

type Plan = {
  id: string; name: string; vehicle_category: string;
  ride_credits: number; price_rs: number; validity_days: number; is_active: boolean;
};

const empty = { name: '', vehicle_category: 'Mini', ride_credits: 50, price_rs: 500, validity_days: 30 };

export default function PlansPage() {
  const [plans, setPlans] = useState<Plan[]>([]);
  const [form, setForm] = useState(empty);
  const [err, setErr] = useState('');

  const load = async () => {
    const { data, error } = await db().from('subscription_plans').select('*').order('price_rs');
    if (error) setErr(error.message);
    else setPlans((data ?? []) as Plan[]);
  };
  useEffect(() => { load(); }, []);

  const save = async () => {
    setErr('');
    const { error } = await db().from('subscription_plans').insert(form);
    if (error) setErr(error.message);
    else { setForm(empty); load(); }
  };

  const toggle = async (p: Plan) => {
    const { error } = await db().from('subscription_plans').update({ is_active: !p.is_active }).eq('id', p.id);
    if (error) setErr(error.message);
    else load();
  };

  return (
    <AdminGate>
    <main>
      <h1>Subscription plans</h1>
      {err && <p style={{ color: 'red' }}>{err}</p>}
      {plans.map((p) => (
        <div key={p.id} style={{ border: '1px solid #ddd', padding: 12, margin: '8px 0' }}>
          <b>{p.name}</b> · {p.vehicle_category} · {p.ride_credits} rides · ₹{p.price_rs} · {p.validity_days}d ·{' '}
          {p.is_active ? 'active' : 'disabled'}{' '}
          <button onClick={() => toggle(p)}>{p.is_active ? 'Disable' : 'Enable'}</button>
        </div>
      ))}
      <h2>New plan</h2>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
        <input placeholder="Name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
        <select value={form.vehicle_category} onChange={(e) => setForm({ ...form, vehicle_category: e.target.value })}>
          {['Bike', 'Auto', 'Mini', 'Sedan', 'SUV'].map((c) => <option key={c}>{c}</option>)}
        </select>
        <input type="number" placeholder="Credits" value={form.ride_credits}
          onChange={(e) => setForm({ ...form, ride_credits: +e.target.value })} />
        <input type="number" placeholder="Price ₹" value={form.price_rs}
          onChange={(e) => setForm({ ...form, price_rs: +e.target.value })} />
        <input type="number" placeholder="Validity days" value={form.validity_days}
          onChange={(e) => setForm({ ...form, validity_days: +e.target.value })} />
        <button onClick={save}>Create</button>
      </div>
    </main>
    </AdminGate>
  );
}
