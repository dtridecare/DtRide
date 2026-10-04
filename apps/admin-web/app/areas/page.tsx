'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
import AdminGate from '../../lib/AdminGate';

const db = () =>
  createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);

type Area = {
  id: string; name: string; city: string;
  center: { type: string; coordinates: [number, number] } | string | null;
  radius_m: number; is_active: boolean;
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

  const load = async () => {
    try {
      const { data, error } = await db().from('service_areas').select('*').order('created_at');
      if (error) setErr(error.message);
      else setRows((data ?? []) as Area[]);
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Failed to load areas. Check connection.');
    }
  };
  useEffect(() => { load(); }, []);

  const create = async () => {
    setErr('');
    const la = parseFloat(lat), lo = parseFloat(lon);
    const km = Number(radiusKm);
    if (!name.trim() || !city.trim() || isNaN(la) || isNaN(lo) || !(km > 0)) {
      setErr('Fill name, city, center coordinates and a positive radius.');
      return;
    }
    try {
      const { error } = await db().from('service_areas').insert({
        name: name.trim(), city: city.trim(),
        center: `SRID=4326;POINT(${lo} ${la})`,
        radius_m: Math.round(km * 1000),
      });
      if (error) setErr(error.message);
      else { setName(''); setCity(''); setLat(''); setLon(''); load(); }
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Create failed. Check connection.');
    }
  };

  const toggle = async (a: Area) => {
    setErr('');
    try {
      const { error } = await db().from('service_areas').update({ is_active: !a.is_active }).eq('id', a.id);
      if (error) setErr(error.message);
      else load();
    } catch (e) {
      setErr(e instanceof Error ? e.message : 'Update failed. Check connection.');
    }
  };

  return (
    <AdminGate>
      <h1 className="text-2xl font-bold mb-1">Service areas</h1>
      <p className="text-sm text-slate-500 mb-6">
        Rides require pickup <b>and</b> drop inside one active area. Add a row per city to expand.
      </p>
      {err && <p className="text-red-600 text-sm mb-4">{err}</p>}
      <div className="grid gap-2 mb-6">
        {rows.map((a) => (
          <div key={a.id} className="card flex flex-wrap items-center gap-3">
            <div className="flex-1 min-w-52">
              <b>{a.name}</b> <span className="text-sm text-slate-500">· {a.city}</span>
              <div className="text-sm text-slate-500">
                {fmtCenter(a.center)}
                {' · '}radius {(a.radius_m / 1000).toFixed(0)} km
              </div>
            </div>
            <span className={`badge ${a.is_active ? 'bg-emerald-100 text-emerald-700' : 'bg-slate-200 text-slate-600'}`}>
              {a.is_active ? 'live' : 'paused'}
            </span>
            <button className="btn-outline !px-3 !py-1" onClick={() => toggle(a)}>
              {a.is_active ? 'Pause' : 'Activate'}
            </button>
          </div>
        ))}
        {rows.length === 0 && <div className="card text-sm text-slate-500">No areas — rides are blocked everywhere until you add one.</div>}
      </div>
      <div className="card">
        <div className="font-semibold mb-3">New service area</div>
        <div className="flex flex-wrap gap-2">
          <input className="input" placeholder="Name (e.g. South Delhi zone)" value={name} onChange={(e) => setName(e.target.value)} />
          <input className="input w-36" placeholder="City" value={city} onChange={(e) => setCity(e.target.value)} />
          <input className="input w-32" placeholder="Center lat" value={lat} onChange={(e) => setLat(e.target.value)} />
          <input className="input w-32" placeholder="Center lon" value={lon} onChange={(e) => setLon(e.target.value)} />
          <input className="input w-28" type="number" placeholder="Radius km" value={radiusKm} onChange={(e) => setRadiusKm(+e.target.value)} />
          <button className="btn-primary" onClick={create}>Add area</button>
        </div>
        <p className="text-xs text-slate-400 mt-2">Tip: right-click any point on openstreetmap.org → “Show address” gives coordinates.</p>
      </div>
    </AdminGate>
  );
}
