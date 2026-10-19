'use client';

import { supabaseAdmin } from '../lib/supabase';
import AdminGate from '../lib/AdminGate';
import { useEffect, useState } from 'react';

export const dynamic = 'force-dynamic';

type DriverRow = {
  id: string;
  kyc_status: string;
  vehicle_category: string;
  upi_id: string | null;
  online: boolean;
  blocked_until: string | null;
  strikes: number;
  profiles: any;
};

export default function UsersPage() {
  const db = supabaseAdmin;
  const [drivers, setDrivers] = useState<DriverRow[]>([]);
  const [filter, setFilter] = useState('all');
  const [search, setSearch] = useState('');

  async function loadDrivers() {
    try {
      const { data } = await supabaseAdmin.from('drivers').select('id, kyc_status, vehicle_category, online, strikes, blocked_until, profiles!inner(full_name, phone), upi_id').order('created_at', { ascending: false });
      setDrivers(data as DriverRow[]);
    } catch (_) {}
  }

  async function toggleDriver(driverId: string, online: boolean) {
    await db.from('drivers').update({ online }).eq('id', driverId);
    await loadDrivers();
  }

  async function blockDriver(driverId: string, block: boolean) {
    await db.from('drivers').update({ blocked_until: block ? new Date(Date.now() + 86400000).toISOString() : null }).eq('id', driverId);
    await loadDrivers();
  }

  async function deleteDriver(driverId: string) {
    if (!confirm('Are you sure you want to delete this driver?')) return;
    await db.from('drivers').delete().eq('id', driverId);
    await loadDrivers();
  }

  useEffect(() => {
    loadDrivers();
  }, []);

  const filteredDrivers = drivers.filter((d) => {
    const prof = d.profiles?.[0] || {};
    const matchSearch = prof.full_name?.toLowerCase().includes(search.toLowerCase()) || prof.phone?.includes(search);
    const matchFilter = filter === 'all' || d.kyc_status === filter || (filter === 'online' && d.online);
    return matchSearch && matchFilter;
  });

  return (
    <div className="space-y-6">
      <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center gap-4 mb-6">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Users & Drivers</h1>
          <p className="text-sm text-slate-500">Manage driver accounts, KYC status, and platform access.</p>
        </div>
        <div className="flex items-center gap-2">
          <input
            type="text"
            placeholder="Search drivers..."
            className="border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4 mb-6">
        {(['all', 'approved', 'pending', 'rejected', 'online'] as const).map((f) => (
          <button
            key={f[0]}
            onClick={() => setFilter(f[0] as any)}
            className={`px-3 py-2 text-sm font-medium rounded-lg transition-colors ${filter === f[0] ? 'bg-blue-600 text-white' : 'bg-white border border-slate-200 text-slate-600 hover:bg-slate-50'}`}
          >
            {f[1]}
          </button>
        ))}
      </div>

      <div className="card p-0">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead className="text-slate-400 border-b border-slate-200">
              <tr>
                <th className="px-4 py-3 font-medium">Driver</th>
                <th className="th px-4 py-3 font-medium">Phone</th>
                <th className="th px-4 py-3 text-left">Category</th>
                <th className="th px-4 py-3 text-left">KYC</th>
                <th className="th px-4 py-3 text-left">Status</th>
                <th className="th px-4 py-3 text-left">Rides Left</th>
                <th className="th px-4 py-3 text-center">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredDrivers.map((d) => {
                const prof = d.profiles?.[0] || {};
                const isBlocked = d.blocked_until && new Date(d.blocked_until) > new Date();
                return (
                  <tr key={d.id} className="border-b border-slate-50 hover:bg-slate-50/50 transition-colors">
                    <td className="px-4 py-3 flex items-center gap-3">
                      <div className="w-8 h-8 rounded-full bg-slate-200 flex items-center justify-center text-xs font-bold text-slate-600">
                        {prof.full_name?.[0] || '?'}
                      </div>
                      <div className="flex-1">
                        <div className="text-sm font-medium text-slate-900">{prof.full_name ?? 'Unknown'}</div>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-sm">{prof.phone ?? '—'}</td>
                    <td className="td px-4 py-3">{d.vehicle_category}</td>
                    <td className="td px-4 py-3">
                      <span className={`badge ${d.kyc_status === 'approved' ? 'bg-emerald-100 text-emerald-700' : d.kyc_status === 'rejected' ? 'bg-red-100 text-red-700' : 'bg-amber-100 text-amber-700'}`}>
                        {d.kyc_status}
                      </span>
                    </td>
                    <td className="td px-4 py-3">
                      {d.online ? (
                        <span className="flex items-center gap-1">
                          <span className="inline-block h-2 w-2 rounded-full bg-emerald-500"></span>
                          <span className="text-xs font-medium text-emerald-600">Online</span>
                        </span>
                      ) : (
                        <span className="text-slate-400 text-sm">Offline</span>
                      )}
                    </td>
                    <td className="td px-4 py-3">{d.strikes}</td>
                    <td className="td px-4 py-3">
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => toggleDriver(d.id, !d.online)}
                          className="px-2 py-1 text-xs rounded border border-slate-200 hover:bg-slate-100 text-sm"
                          disabled={d.blocked_until ? true : false}
                        >
                          {d.online ? 'Offline' : 'Online'}
                        </button>
                        <button
                          onClick={() => blockDriver(d.id, !isBlocked)}
                          className="px-2 py-1 text-xs rounded border border-slate-200 hover:bg-red-50 hover:text-red-600 text-sm"
                        >
                          {isBlocked ? 'Unblock' : 'Block'}
                        </button>
                        <button
                          onClick={() => deleteDriver(d.id)}
                          className="px-2 py-1 text-xs rounded border border-slate-200 hover:bg-red-50 hover:text-red-600 text-sm">
                          Delete
                        </button>
                      </div>
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
}
