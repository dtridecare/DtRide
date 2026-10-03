'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
import SignOutButton from './SignOutButton';

const NAV = [
  { href: '/', label: 'Dashboard' },
  { href: '/kyc', label: 'KYC' },
  { href: '/plans', label: 'Plans' },
  { href: '/fares', label: 'Fares' },
  { href: '/rides', label: 'Live rides' },
  { href: '/disputes', label: 'Disputes' },
  { href: '/coupons', label: 'Coupons' },
];

export default function Nav() {
  const [mode, setMode] = useState<'loading' | 'signed-out' | 'admin' | 'user'>('loading');

  useEffect(() => {
    const c = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    c.auth.getUser().then(async ({ data }) => {
      if (!data.user) {
        setMode('signed-out');
        return;
      }
      const { data: p } = await c.from('profiles').select('is_admin').eq('id', data.user.id).single();
      setMode(p?.is_admin ? 'admin' : 'user');
    }).catch(() => setMode('signed-out'));
  }, []);

  const links = mode === 'admin' ? NAV : [];
  const row = 'flex gap-4 overflow-x-auto text-sm';

  return (
    <>
      <aside className="w-60 shrink-0 bg-slate-900 text-slate-200 p-5 hidden md:block">
        <div className="text-xl font-bold text-white mb-1">DT Ride</div>
        <div className="text-xs text-slate-400 mb-6">Ops console</div>
        {mode === 'admin' && (
          <nav className="flex flex-col gap-1">
            {links.map((n) => (
              <a key={n.href} href={n.href}
                className="rounded-lg px-3 py-2 text-sm hover:bg-slate-800 hover:text-white">
                {n.label}
              </a>
            ))}
          </nav>
        )}
        <div className="mt-6">
          {mode === 'signed-out' && <a href="/login" className="text-sm text-slate-300 underline">Sign in</a>}
          {(mode === 'admin' || mode === 'user') && <SignOutButton className="btn-outline !text-slate-200 !border-slate-700 hover:!bg-slate-800 text-sm" />}
        </div>
      </aside>
      <header className="md:hidden bg-slate-900 text-slate-200 px-4 py-3 flex gap-4 overflow-x-auto text-sm items-center">
        <span className="font-bold whitespace-nowrap">DT Ride</span>
        <span className={row}>
          {links.map((n) => <a key={n.href} href={n.href} className="whitespace-nowrap">{n.label}</a>)}
        </span>
      </header>
    </>
  );
}
