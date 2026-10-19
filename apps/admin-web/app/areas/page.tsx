'use client';

import { useEffect, useState } from 'react';
import { supabaseAdmin } from '../lib/supabase';

type Area = {
  id: string;
  name: string;
  city: string;
  center: { type: string; coordinates: [number, number] } | string | null;
  radius_m: number;
  is_active: boolean;
};

function fmtCenter(c: Area['center']): string {
  if (!c) return '—';
  if (typeof c === 'string') {
    const m = /POINT\(([-\d.]+) ([-\d.]+)\)/.exec(c);
    return m ? `${(+m[2]).toFixed(4)}, ${(+m[1]).toFixed(4)}` : c;
  }
  const coords = c.coordinates;
  if (!Array.isArray(coords) || coords.length < 2) return '—';
  return `${(+coords[1]).toFixed(4)}, ${(+coords[0]).toFixed(4)}`;
}

export default function AreasPage() {
  const [rows, setRows] = useState<Area[]>([]);
  const [name, setName] = useState('');
  const [city, setCity] = useState('');
  const [lat, setLat] = useState('');
  const [lon, setLon] = useState('');
  const [radiusKm, setRadiusKm] = useState(40);
  const [err, setErr] = useState('');
  const [loading, setLoading] = useState(true);

  const load = async () => {
    try {
      const { data } = await supabaseAdmin.from('service_areas').select('*').order('created_at');
      setRows((data ?? []) as Area[]);
    } catch (_) {}
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const create = async () => {
    setErr('');
    const la = parseFloat(lat);
    const lo = parseFloat(lon);
    const km = Number(radiusKm);
    if (!name.trim() || !city.trim() || isNaN(la) || isNaN(lo) || !(km > 0)) {
      setErr('Fill name, city, center coordinates and a positive radius.');
      return;
    }
    try {
      const { error } = await supabaseAdmin.from('service_areas').insert({
        name: name.trim(), city: city.trim(),
        center: `SRID=4326;POINT(${lo} ${la})`,
        radius_m: Math.round(km * 1000),
      });
      if (error) setErr(error.message);
      else { setName(''); setCity(''); setLat(''); setLon(''); setRadiusKm(40); load(); }
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Create failed.');
    }
  };

  const toggle = async (a: Area) => {
    setErr('');
    try {
      const { error } = await supabaseAdmin.from('service_areas').update({ is_active: !a.is_active }).eq('id', a.id);
      if (error) setErr(error.message);
      else load();
    } catch (_) {}
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col lg:flex-row justify-between items-start lg:items-center gap-4 mb-6">
        <div>
          <h1 className="text-2xl font-bold text-slate-900">Service Areas</h1>
          <p className="text-sm text-slate-500">Rides require pickup <b>and</b> drop inside one active area. Add areas to enable rides.</p>
        </div>
      </div>

      <div className="card p-6">
        <div className="flex flex-wrap gap-4">
          <input type="text" placeholder="Area name (e.g. South Delhi zone)"
            className="border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            value={name} onChange={(e) => setName(e.target.value)} />
          <input type="text" placeholder="City"
            className="border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            value={city} onChange={(e) => setCity(e.target.value)} />
          <input type="text" placeholder="Center lat"
            className="border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            value={lat} onChange={(e) => setLat(e.target.value)} />
          <input type="text" placeholder="Center lon"
            className="border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            value={lon} onChange={(e) => setLon(e.target.value)} />
          <input type="number" placeholder="Radius km"
            className="border border-slate-300 rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            value={radiusKm} onChange={(e) => setRadiusKm(+e.target.value)} />
          <button className="bg-blue-600 text-white px-4 py-2 text-sm font-medium rounded-lg hover:bg-blue-700"
            onClick={create}>Add area</button>
        </div>
        <p className="text-xs text-slate-400 mt-2">Tip: right-click any point on OpenStreetMap → "What's here?" to get coordinates.</p>
      </div>

      <div className="grid gap-2">
        {rows.map((a) => (
          <div key={a.id} className="card p-4 flex items-center justify-between gap-4">
            <div className="flex-1">
              <div className="flex items-center gap-2 font-medium text-slate-900">
                <span>{a.name}</span>
                <span className="text-sm text-slate-500">· {a.city}</span>
              </div>
              <div className="text-sm text-slate-500">{fmtCenter(a.center)} · radius {(a.radius_m / 1000).toFixed(0)} km</div>
            </div>
            <span className={`badge ${a.is_active ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-200 text-slate-600'}`}>
              {a.is_active ? 'Live' : 'Paused'}
            </span>
            <button
              className="px-2 py-1 text-xs rounded border border-slate-200 hover:bg-slate-100"
              onClick={() => toggle(a)}
            >
              {a.is_active ? 'Pause' : 'Activate'}
            </button>
          </div>
        ))}
        {rows.length === 0 && <div className="card p-6 text-sm text-slate-500">No areas — rides are blocked everywhere until you add one.</div>}
      </div>
    </div>
  );
}
