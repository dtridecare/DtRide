// POST /functions/v1/notify-ride — called by APPS with the USER's JWT
// (verify_jwt stays on). Validates the caller is on the ride, composes the
// message server-side from DB state, fans out via send-push.
// Body: { ride_id: string, event: 'accepted'|'arrived'|'started'|'completed'|'cancelled'|'offer'|'offer_accepted' }
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req) => {
  const supa = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );
  const { data: { user } } = await supa.auth.getUser();
  if (!user) return new Response("unauthorized", { status: 401 });
  const { ride_id, event } = await req.json();

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: ride } = await admin.from("rides").select("*").eq("id", ride_id).single();
  if (!ride) return new Response("ride not found", { status: 404 });
  if (ride.rider_id !== user.id && ride.driver_id !== user.id) {
    return new Response("not your ride", { status: 403 });
  }

  const fare = `₹${ride.fare_estimate_rs ?? "?"}`;
  const msgs: Record<string, { to: string[]; title: string; body: string }> = {
    accepted: { to: [ride.rider_id], title: "Driver accepted", body: `Your ${ride.category} is on the way · ${fare}` },
    arrived: { to: [ride.rider_id], title: "Driver arrived", body: `Share your OTP to start · ${fare}` },
    started: { to: [ride.rider_id], title: "Ride started", body: "Enjoy your trip — pay the driver directly" },
    completed: { to: [ride.rider_id], title: "Ride completed", body: `Please rate your driver · ${fare} paid direct` },
    cancelled: {
      to: [(ride.rider_id === user.id ? ride.driver_id : ride.rider_id)].filter(Boolean),
      title: "Ride cancelled", body: "The other party cancelled this ride",
    },
    offer: { to: [ride.rider_id], title: "New driver offer", body: "A driver countered your bid — open to review" },
    offer_accepted: {
      to: ride.driver_id ? [ride.driver_id] : [],
      title: "Offer accepted", body: `Rider accepted ${fare} — head to pickup`,
    },
  };
  const m = msgs[event];
  if (!m || m.to.length === 0) return Response.json({ ok: true, skipped: true });

  const secret = Deno.env.get("PUSH_SECRET") ?? "";
  await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/send-push`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-push-secret": secret },
    body: JSON.stringify({
      user_ids: m.to, title: m.title, body: m.body,
      kind: "ride", data: { ride_id, type: event },
    }),
  }).catch(() => null);
  return Response.json({ ok: true });
});
