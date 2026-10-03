'use client';
import { useState } from 'react';
import { createClient } from '@supabase/supabase-js';

export default function LoginPage() {
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [sent, setSent] = useState(false);
  const [err, setErr] = useState('');

  const c = () =>
    createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);

  const send = async () => {
    setErr('');
    const { error } = await c().auth.signInWithOtp({ email: email.trim() });
    if (error) setErr(error.message);
    else setSent(true);
  };

  const verify = async () => {
    setErr('');
    const { error } = await c().auth.verifyOtp({ email: email.trim(), token: code.trim(), type: 'email' });
    if (error) setErr(error.message);
    else window.location.href = '/';
  };

  return (
    <div className="max-w-md mx-auto mt-16 card">
      <h1 className="text-2xl font-bold mb-1">Admin login</h1>
      <p className="text-sm text-slate-500 mb-4">Ops accounts need <code>profiles.is_admin = true</code> (set once in SQL).</p>
      {err && <p className="text-red-600 text-sm mb-3">{err}</p>}
      <input className="input w-full mb-2" placeholder="admin@example.com"
        value={email} onChange={(e) => setEmail(e.target.value)} />
      {sent && <input className="input w-full mb-2" placeholder="6-digit code"
        value={code} onChange={(e) => setCode(e.target.value)} />}
      <button className="btn-primary w-full" onClick={sent ? verify : send}>{sent ? 'Verify' : 'Send code'}</button>
    </div>
  );
}
