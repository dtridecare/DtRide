'use client';
import { useState } from 'react';
import { createClient } from '@supabase/supabase-js';

export default function LoginPage() {
  const [email, setEmail] = useState('');
  const [sent, setSent] = useState(false);
  const [err, setErr] = useState('');

  const c = () =>
    createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);

  const send = async () => {
    setErr('');
    const { error } = await c().auth.signInWithOtp({
      email: email.trim(),
      options: { emailRedirectTo: window.location.origin },
    });
    if (error) setErr(error.message);
    else setSent(true);
  };

  return (
    <div className="max-w-md mx-auto mt-16 card">
      <h1 className="text-2xl font-bold mb-1">Admin login</h1>
      <p className="text-sm text-slate-500 mb-4">Ops accounts need <code>profiles.is_admin = true</code> (set once in SQL).</p>
      {err && <p className="text-red-600 text-sm mb-3">{err}</p>}
      {!sent ? (
        <>
          <input className="input w-full mb-2" placeholder="admin@example.com"
            value={email} onChange={(e) => setEmail(e.target.value)} />
          <button className="btn-primary w-full" onClick={send}>Email me a login link</button>
        </>
      ) : (
        <p className="text-sm">
          Check <b>{email}</b> and click the login link
          <b> on this device</b> — you&apos;ll land back here logged in.
        </p>
      )}
    </div>
  );
}
