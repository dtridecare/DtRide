'use client';
import { createClient } from '@supabase/supabase-js';

export default function SignOutButton({ className }: { className?: string }) {
  const out = async () => {
    const c = createClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
    await c.auth.signOut();
    window.location.href = '/';
  };
  return <button className={className ?? 'btn-outline'} onClick={out}>Sign out</button>;
}
