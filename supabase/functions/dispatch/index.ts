import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// POST /functions/v1/dispatch { ride_id } — expand radius 3/5/8km,
// push new-request alerts to eligible drivers, return them.
// Called by apps (user JWT) right after create_ride.
serve(async (req) => {
  const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { ride_id } = await req.json();
  const { data: ride } = await supa.from("rides").select("*").eq("id", ride_id).single();
  if (!ride) return new Response("ride not found", { status: 404 });
  if (ride.status !== "requested") return Response.json({ drivers: [], skipped: "not requested" });

  const radii = [3000, 5000, 8000];
  for (const r of radii) {
    const { data } = await supa.rpc("nearby_drivers", {
      p_pickup: ride.pickup, p_radius_m: r, p_category: ride.category,
    });
    if (data?.length) {
      const drivers = (data as { driver_id: string }[]).slice(0, 10);
      const secret = Deno.env.get("PUSH_SECRET") ?? "";
      await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/send-push`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-push-secret": secret },
        body: JSON.stringify({
          user_ids: drivers.map((d) => d.driver_id),
          title: `New ${ride.category} request · ₹${ride.fare_estimate_rs ?? "?"}`,
          body: `${ride.pickup_text ?? "Pickup"} → ${ride.drop_text ?? "Drop"}`,
          kind: "new_request",
          data: { ride_id, type: "new_request" },
        }),
      }).catch(() => null);
      return Response.json({ radius_m: r, drivers });
    }
  }
  await supa.from("rides").update({ status: "no_driver_found" }).eq("id", ride_id);
  return Response.json({ drivers: [] });
});
