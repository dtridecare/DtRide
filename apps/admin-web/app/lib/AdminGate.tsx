'use client';

import { useEffect, useState } from 'react';
import { supabaseAdmin } from './supabase';

export default function AdminGate({ children }: { children: React.ReactNode }) {
  const [loading, setLoading] = useState(true);
  const [isAdmin, setIsAdmin] = useState(false);

  useEffect(() => {
    const checkAdmin = async () => {
      try {
        const { data: { user }, error } = await supabaseAdmin.auth.getUser();
        if (error || !user) {
          setIsAdmin(false);
          setLoading(false);
          return;
        }
        const { data: profile } = await supabaseAdmin.from('profiles').select('is_admin').eq('id', user.id).single();
        setIsAdmin(profile?.is_admin ?? false);
      } catch (_) {
        setIsAdmin(false);
      } finally {
        setLoading(false);
      }
    };
    checkAdmin();
  }, []);

  if (loading) return <div className="h-screen flex items-center justify-center">Loading…</div>;
  if (!isAdmin) return <div className="p-4 text-center">Admin access required</div>;
  return <>{children}</>;
}
