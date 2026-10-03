// POST /functions/v1/razorpay-webhook — verify signature, activate subscription.
// Set RAZORPAY_WEBHOOK_SECRET via `supabase secrets set`.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

async function verify(raw: string, sig: string, secret: string): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(raw));
  const hex = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return hex === sig;
}

serve(async (req) => {
  const secret = Deno.env.get("RAZORPAY_WEBHOOK_SECRET") ?? "";
  const sig = req.headers.get("x-razorpay-signature") ?? "";
  const raw = await req.text();
  if (!secret || !(await verify(raw, sig, secret))) {
    return new Response("bad signature", { status: 401 });
  }
  const evt = JSON.parse(raw);
  if (evt.event !== "payment.captured") return Response.json({ ok: true, ignored: evt.event });

  const payment = evt.payload.payment.entity;
  const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: pay } = await supa.from("payments")
    .select("*, driver_subscriptions!inner(id, plan_id, subscription_plans!inner(validity_days))")
    .eq("razorpay_order_id", payment.order_id).single();
  if (!pay) return new Response("order not found", { status: 404 });

  const days = pay.driver_subscriptions.subscription_plans.validity_days;
  await supa.from("driver_subscriptions").update({
    status: "active",
    starts_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + days * 864e5).toISOString(),
  }).eq("id", pay.subscription_id);
  await supa.from("payments").update({
    status: "completed", razorpay_payment_id: payment.id,
  }).eq("id", pay.id);
  return Response.json({ ok: true });
});
