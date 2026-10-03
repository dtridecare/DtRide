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
      <h1 className="text-2xl font-bold mb-1">Subscription plans</h1>
      <p className="text-sm text-slate-500 mb-6">Price per vehicle category — drivers buy ride credits.</p>
      {err && <p className="text-red-600 text-sm mb-4">{err}</p>}
      <div className="card !p-0 overflow-hidden mb-6">
        <table className="w-full">
          <thead><tr><th className="th">Plan</th><th className="th">Category</th><th className="th">Rides</th><th className="th">Price</th><th className="th">Validity</th><th className="th">Status</th><th className="th"></th></tr></thead>
          <tbody>
            {plans.map((p) => (
              <tr key={p.id}>
                <td className="td font-medium">{p.name}</td>
                <td className="td">{p.vehicle_category}</td>
                <td className="td">{p.ride_credits}</td>
                <td className="td">₹{p.price_rs}</td>
                <td className="td">{p.validity_days}d</td>
                <td className="td">
                  <span className={`badge ${p.is_active ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-200 text-slate-600'}`}>
                    {p.is_active ? 'active' : 'disabled'}
                  </span>
                </td>
                <td className="td"><button className="btn-outline !px-3 !py-1" onClick={() => toggle(p)}>{p.is_active ? 'Disable' : 'Enable'}</button></td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="card">
        <div className="font-semibold mb-3">New plan</div>
        <div className="flex flex-wrap gap-2">
          <input className="input" placeholder="Name" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} />
          <select className="input" value={form.vehicle_category} onChange={(e) => setForm({ ...form, vehicle_category: e.target.value })}>
            {['Bike', 'Auto', 'Mini', 'Sedan', 'SUV'].map((c) => <option key={c}>{c}</option>)}
          </select>
          <input className="input w-28" type="number" placeholder="Credits" value={form.ride_credits}
            onChange={(e) => setForm({ ...form, ride_credits: +e.target.value })} />
          <input className="input w-28" type="number" placeholder="Price ₹" value={form.price_rs}
            onChange={(e) => setForm({ ...form, price_rs: +e.target.value })} />
          <input className="input w-32" type="number" placeholder="Days" value={form.validity_days}
            onChange={(e) => setForm({ ...form, validity_days: +e.target.value })} />
          <button className="btn-primary" onClick={save}>Create</button>
        </div>
      </div>
    </AdminGate>
  );
}
