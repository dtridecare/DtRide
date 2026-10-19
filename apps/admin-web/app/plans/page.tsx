'use client';

import { useEffect, useState } from 'react';
import { supabaseAdmin } from '../lib/supabase';

type Plan = {
  id: string;
  name: string;
  vehicle_category: string;
  ride_credits: number;
  price_rs: number;
  validity_days: number;
  is_active: boolean;
};

export default function PlansPage() {
  const [plans, setPlans] = useState<Plan[]>([]);
  const [form, setForm] = useState({
    name: '',
    vehicle_category: 'Mini',
    ride_credits: 50,
    price_rs: 500,
    validity_days: 30,
  });
  const [err, setErr] = useState('');
  const [loading, setLoading] = useState(true);

  const load = async () => {
    try {
      const { data, error } = await supabaseAdmin.from('subscription_plans').select('*').order('price_rs');
      if (error) setErr(error.message);
      else setPlans((data ?? []) as Plan[]);
    } catch (_) {}
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const save = async () => {
    setErr('');
    try {
      const { error } = await supabaseAdmin.from('subscription_plans').insert(form);
      if (error) setErr(error.message);
      else { setForm({ name: '', vehicle_category: 'Mini', ride_credits: 50, price_rs: 500, validity_days: 30 }); load(); }
    } catch (_) {}
  };

  const toggle = async (p: Plan) => {
    try {
      const { error } = await supabaseAdmin.from('subscription_plans').update({ is_active: !p.is_active }).eq('id', p.id);
      if (error) setErr(error.message);
      else load();
    } catch (_) {}
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center gap-4 mb-6">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Subscription Plans</h1>
          <p className="text-sm text-slate-500">Manage subscription plans — riders buy ride credits per vehicle category.</p>
        </div>
        <div className="flex items-center gap-2">
          <button
            className="flex items-center gap-2 px-3 py-2 text-sm font-medium text-slate-600 rounded-lg border border-slate-200 hover:bg-slate-100"
            onClick={load}
          >
            <span className="material-symbols-rounded text-sm">refresh</span>
            <span className="hidden sm:block">Refresh</span>
          </button>
        </div>
      </div>

      {err && (
        <div className="px-4 py-3 rounded-lg bg-red-50 border border-red-200 text-red-700 text-sm mb-6">
          {err}
        </div>
      )}

      <div className="card !p-0 overflow-hidden mb-6">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="text-slate-400 border-b border-slate-100">
                <th className="px-4 py-3 font-medium">Plan Name</th>
                <th className="th px-4 py-3 text-left">Category</th>
                <th className="th px-4 py-3 text-left">Rides</th>
                <th className="th px-4 py-3 text-left">Price</th>
                <th className="th px-4 py-3 text-left">Validity</th>
                <th className="th px-4 py-3 text-left">Status</th>
                <th className="th px-4 py-3 text-left">Action</th>
              </tr>
            </thead>
            <tbody>
              {plans.map((p) => (
                <tr key={p.id} className="border-b border-slate-50 hover:bg-slate-50/50">
                  <td className="px-4 py-3 font-medium">{p.name}</td>
                  <td className="td px-4 py-3">{p.vehicle_category}</td>
                  <td className="td px-4 py-3">{p.ride_credits}</td>
                  <td className="td px-4 py-3 font-medium">₹{p.price_rs}</td>
                  <td className="td px-4 py-3">{p.validity_days} days</td>
                  <td className="td px-4 py-3">
                    <span className={`badge ${p.is_active ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-200 text-slate-600'}`}>
                      {p.is_active ? 'Active' : 'Disabled'}
                    </span>
                  </td>
                  <td className="td px-4 py-3">
                    <button
                      className="px-2 py-1 text-xs font-medium rounded border border-slate-200 hover:bg-slate-100"
                      onClick={() => toggle(p)}
                    >
                      {p.is_active ? 'Disable' : 'Enable'}
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <div className="card p-6">
        <div className="flex flex-wrap items-center gap-4 mb-4">
          <div className="flex-1 min-w-[200px]">
            <h3 className="text-sm font-semibold text-slate-700 mb-2">Create New Plan</h3>
          </div>
          <div className="flex gap-2 flex-wrap">
            <input
              type="text"
              placeholder="Plan name"
              className="border border-slate-200 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
            />
            <select
              className="border border-slate-200 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              value={form.vehicle_category}
              onChange={(e) => setForm({ ...form, vehicle_category: e.target.value })}
            >
              {['Bike', 'Auto', 'Mini', 'Sedan', 'SUV'].map((c) => (
                <option key={c}>{c}</option>
              ))}
            </select>
            <input
              type="number"
              placeholder="Credits"
              className="border border-slate-200 rounded-lg px-3 py-2 text-sm w-32 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              value={form.ride_credits}
              onChange={(e) => setForm({ ...form, ride_credits: +e.target.value })}
            />
            <input
              type="number"
              placeholder="Price (₹)"
              className="border border-slate-200 rounded-lg px-3 py-2 text-sm w-40 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              value={form.price_rs}
              onChange={(e) => setForm({ ...form, price_rs: +e.target.value })}
            />
            <input
              type="number"
              placeholder="Days"
              className="border border-slate-200 rounded-lg px-3 py-2 text-sm w-32 focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              value={form.validity_days}
              onChange={(e) => setForm({ ...form, validity_days: +e.target.value })}
            />
            <button
              className="bg-blue-600 text-white px-4 py-2 text-sm font-medium rounded-lg hover:bg-blue-700 transition-colors"
              onClick={save}
            >
              Create Plan
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
