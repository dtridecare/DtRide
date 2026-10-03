'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
import SignOutButton from './SignOutButton';

type Props = {
  children: React.ReactNode;
  /** Shown when nobody is signed in (landing defaults to login form). */
  signedOut?: React.ReactNode;
};

export default function AdminGate({ children, signedOut }: Props) {
  const [state, setState] = useState<'loading' | 'ok' | 'signed-out' | 'forbidden'>('loading');

  useEffect(() => {
    const c = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    c.auth.getUser().then(async ({ data }) => {
      if (!data.user) {
        setState('signed-out');
        return;
      }
      const { data: p } = await c.from('profiles').select('is_admin').eq('id', data.user.id).single();
      setState(p?.is_admin ? 'ok' : 'forbidden');
    }).catch(() => setState('signed-out'));
  }, []);

  if (state === 'loading') return <div className="card text-sm text-slate-500">Checking access…</div>;
  if (state === 'signed-out') {
    return <>{signedOut ?? <p className="text-sm">Please <a className="text-indigo-600 underline" href="/login">sign in</a>.</p>}</>;
  }
  if (state === 'forbidden') {
    return (
      <div className="card text-sm max-w-md mx-auto mt-16 text-center">
        <h1 className="text-xl font-bold mb-2">No ops access</h1>
        <p className="text-slate-500 mb-4">This account isn&apos;t an admin. Contact your administrator.</p>
        <SignOutButton />
      </div>
    );
  }
  return <>{children}</>;
}
