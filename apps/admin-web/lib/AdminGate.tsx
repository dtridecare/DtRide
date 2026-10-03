'use client';
import { useEffect, useState } from 'react';
import { createClient } from '@supabase/supabase-js';

export default function AdminGate({ children }: { children: React.ReactNode }) {
  const [state, setState] = useState<'loading' | 'ok' | 'denied'>('loading');

  useEffect(() => {
    const c = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    c.auth.getUser().then(async ({ data }) => {
      if (!data.user) {
        setState('denied');
        return;
      }
      const { data: p } = await c.from('profiles').select('is_admin').eq('id', data.user.id).single();
      setState(p?.is_admin ? 'ok' : 'denied');
    }).catch(() => setState('denied'));
  }, []);

  if (state === 'loading') return <p>Checking admin access…</p>;
  if (state === 'denied') {
    return (
      <p>
        Admin access required. <a href="/login">Login</a> with an ops account
        (<code>profiles.is_admin = true</code>).
      </p>
    );
  }
  return <>{children}</>;
}
