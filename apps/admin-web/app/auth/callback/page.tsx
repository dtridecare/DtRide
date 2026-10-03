'use client';
import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@supabase/supabase-js';

// Landing page for magic-link redirects. Instantiating the client picks up
// the session from the URL hash; then we bounce to the dashboard.
export default function AuthCallback() {
  const router = useRouter();
  useEffect(() => {
    const c = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    c.auth.getSession().finally(() => router.replace('/'));
  }, [router]);
  return <p className="text-sm text-slate-500">Signing you in…</p>;
}
