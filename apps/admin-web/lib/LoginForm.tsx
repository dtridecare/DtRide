'use client';
import { useEffect, useRef, useState } from 'react';
import { createClient } from '@supabase/supabase-js';

/** Six-box OTP input with auto-advance, backspace nav and paste support. */
function OtpBoxes({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const refs = useRef<(HTMLInputElement | null)[]>([]);
  const digits = Array.from({ length: 6 }, (_, i) => value[i] ?? '');

  const set = (next: string[]) => onChange(next.join('').slice(0, 6));

  const onKey = (i: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Backspace' && !digits[i] && i > 0) refs.current[i - 1]?.focus();
  };

  const onPaste = (e: React.ClipboardEvent) => {
    e.preventDefault();
    const t = e.clipboardData.getData('text').replace(/\D/g, '').slice(0, 6).split('');
    if (t.length) {
      set(t);
      refs.current[Math.min(t.length, 5)]?.focus();
    }
  };

  useEffect(() => { refs.current[0]?.focus(); }, []);

  return (
    <div className="flex gap-2 justify-center" onPaste={onPaste}>
      {digits.map((d, i) => (
        <input
          key={i}
          ref={(el) => { refs.current[i] = el; }}
          className="h-12 w-11 rounded-xl border border-slate-300 text-center text-xl font-bold focus:border-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-200"
          inputMode="numeric"
          maxLength={1}
          value={d}
          onChange={(e) => {
            const ch = e.target.value.replace(/\D/g, '').slice(-1);
            const next = [...digits];
            next[i] = ch;
            set(next);
            if (ch && i < 5) refs.current[i + 1]?.focus();
          }}
          onKeyDown={(e) => onKey(i, e)}
        />
      ))}
    </div>
  );
}

const PERKS = [
  { t: 'Live ride board', d: 'Every requested, accepted and started trip in real time.' },
  { t: 'Driver KYC & plans', d: 'Approve drivers and control subscription pricing.' },
  { t: 'Safety first', d: 'SOS feed, disputes and credit refunds in one place.' },
];

export default function LoginForm() {
  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [sent, setSent] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState('');

  const c = () =>
    createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);

  const send = async () => {
    setErr(''); setBusy(true);
    const { error } = await c().auth.signInWithOtp({
      email: email.trim(),
      options: { emailRedirectTo: `${window.location.origin}/auth/callback` },
    });
    setBusy(false);
    if (error) setErr(error.message);
    else { setSent(true); setCode(''); }
  };

  const verify = async () => {
    if (code.length !== 6) {
      setErr('Enter the 6-digit code.');
      return;
    }
    setErr(''); setBusy(true);
    const { error } = await c().auth.verifyOtp({ email: email.trim(), token: code.trim(), type: 'email' });
    setBusy(false);
    if (error) setErr(error.message);
    else window.location.href = '/';
  };

  return (
    <div className="min-h-[calc(100vh-2rem)] md:min-h-[calc(100vh-3rem)] -m-4 md:-m-6 flex">
      {/* Brand panel */}
      <div className="hidden lg:flex w-[46%] flex-col justify-between bg-slate-950 text-white p-12 relative overflow-hidden">
        <div className="absolute -top-32 -right-32 h-96 w-96 rounded-full bg-indigo-600/30 blur-3xl" />
        <div className="absolute -bottom-40 -left-24 h-96 w-96 rounded-full bg-emerald-500/20 blur-3xl" />
        <div className="relative">
          <div className="flex items-center gap-3">
            <span className="flex h-11 w-11 items-center justify-center rounded-2xl bg-indigo-600 text-xl font-black">DT</span>
            <div>
              <div className="text-xl font-bold leading-tight">DT Ride</div>
              <div className="text-xs text-slate-400">Ops console</div>
            </div>
          </div>
        </div>
        <div className="relative">
          <h1 className="text-4xl font-extrabold leading-tight mb-3">Run your entire<br />ride network.</h1>
          <p className="text-slate-400 mb-8 max-w-sm">Dispatch, drivers, fares, safety and money — one console for your city launch.</p>
          <div className="flex flex-col gap-4">
            {PERKS.map((p) => (
              <div key={p.t} className="flex gap-3">
                <span className="mt-1 flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-emerald-500/20 text-emerald-400 text-sm">✓</span>
                <div>
                  <div className="font-semibold text-sm">{p.t}</div>
                  <div className="text-sm text-slate-400">{p.d}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
        <div className="relative text-xs text-slate-500">Subscription model · No commission · Made for 1000+ users</div>
      </div>

      {/* Form panel */}
      <div className="flex-1 flex items-center justify-center p-6 bg-slate-100">
        <div className="w-full max-w-sm card !p-8">
          <div className="lg:hidden flex items-center gap-2 mb-6">
            <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-indigo-600 text-white font-black">DT</span>
            <span className="font-bold">DT Ride Ops</span>
          </div>
          <h2 className="text-2xl font-bold mb-1">{sent ? 'Check your inbox' : 'Welcome back'}</h2>
          <p className="text-sm text-slate-500 mb-6">
            {sent ? <>Code sent to <b className="text-slate-700">{email}</b></> : 'Sign in with your ops email to continue.'}
          </p>
          {err && <p className="text-red-600 text-sm mb-3">{err}</p>}
          {!sent ? (
            <>
              <label className="text-xs font-semibold text-slate-500">WORK EMAIL</label>
              <input className="input w-full mt-1 mb-3" placeholder="admin@example.com"
                type="email" value={email} onChange={(e) => setEmail(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && send()} />
              <button className="btn-primary w-full !py-2.5" disabled={busy || !email.trim()} onClick={send}>
                {busy ? 'Sending…' : 'Send login code'}
              </button>
            </>
          ) : (
            <>
              <OtpBoxes value={code} onChange={setCode} />
              <button className="btn-primary w-full !py-2.5 mt-4" disabled={busy} onClick={verify}>
                {busy ? 'Verifying…' : 'Verify & enter'}
              </button>
              <button className="w-full text-center text-sm text-slate-500 mt-3 underline" onClick={() => { setSent(false); setCode(''); }}>
                Use a different email
              </button>
            </>
          )}
          <p className="text-xs text-slate-400 mt-6 text-center">New ops member? Ask your administrator for access.</p>
        </div>
      </div>
    </div>
  );
}
