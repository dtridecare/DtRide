// Cron: subscription reminders (low credits + expiring soon).
// Schedule: `supabase functions deploy reminders` + pg_cron / dashboard scheduler, every 6h.
// Inserts into notifications (always) and sends FCM legacy push if FCM_SERVER_KEY is set.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const LOW_AT = [10, 5, 1];

serve(async (_req) => {
  const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const serverKey = Deno.env.get("FCM_SERVER_KEY") ?? "";
  let created = 0;

  const { data: subs } = await supa.from("driver_subscriptions")
    .select("driver_id, credits_total, credits_used, expires_at")
    .eq("status", "active");
  if (!subs) return Response.json({ created: 0 });

  const since = new Date(Date.now() - 24 * 3600e3).toISOString();

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
      const { data: dup } = await supa.from("notifications").select("id")
        .eq("user_id", s.driver_id).eq("kind", j.kind).gte("created_at", since).limit(1);
      if (dup?.length) continue;
      await supa.from("notifications").insert({ user_id: s.driver_id, ...j });
      created++;
      if (serverKey) {
        const { data: tokens } = await supa.from("push_tokens").select("token").eq("user_id", s.driver_id);
        for (const t of tokens ?? []) {
          await fetch("https://fcm.googleapis.com/fcm/send", {
            method: "POST",
            headers: { "Content-Type": "application/json", Authorization: `key=${serverKey}` },
            body: JSON.stringify({ to: t.token, notification: { title: j.title, body: j.body } }),
          }).catch(() => null);
        }
      }
    }
  }
  return Response.json({ created });
});
