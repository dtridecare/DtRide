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
    <main>
      <h1>Admin login</h1>
      <p>Ops accounts need <code>profiles.is_admin = true</code> (set once in SQL).</p>
      {err && <p style={{ color: 'red' }}>{err}</p>}
      <input placeholder="admin@example.com" value={email} onChange={(e) => setEmail(e.target.value)} style={{ width: 280 }} />
      {sent && <input placeholder="6-digit code" value={code} onChange={(e) => setCode(e.target.value)} style={{ width: 160 }} />}
      <button onClick={sent ? verify : send}>{sent ? 'Verify' : 'Send code'}</button>
    </main>
  );
}
