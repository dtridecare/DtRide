// Cron: subscription reminders (low credits + expiring soon).
// Schedule every 6h via Dashboard → Edge Functions → Schedules (or pg_cron).
// Routes through send-push (inbox always, FCM when configured).
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const LOW_AT = [10, 5, 1];

serve(async (_req) => {
  const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const secret = Deno.env.get("PUSH_SECRET") ?? "";
  let created = 0;

  const { data: subs } = await supa.from("driver_subscriptions")
    .select("driver_id, credits_total, credits_used, expires_at")
    .eq("status", "active");
  if (!subs) return Response.json({ created: 0 });

  for (const s of subs) {
    const left = s.credits_total - s.credits_used;
    const days = (new Date(s.expires_at).getTime() - Date.now()) / 864e5;
    const jobs: { kind: string; title: string; body: string }[] = [];
    if (LOW_AT.includes(left)) {
      jobs.push({ kind: "low_credits", title: "Running low on rides",
        body: `Only ${left} ride credits left. Renew your plan to stay online.` });
    }
    if (days > 0 && days < 3) {
      jobs.push({ kind: "expiring", title: "Plan expiring soon",
        body: `Your plan expires in ${Math.ceil(days)} day(s) with ${left} credits left.` });
    }
    for (const j of jobs) {
      const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/send-push`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-push-secret": secret },
        body: JSON.stringify({ user_ids: [s.driver_id], ...j }),
      }).catch(() => null);
      if (res?.ok) created++;
    }
  }
  return Response.json({ created });
});
