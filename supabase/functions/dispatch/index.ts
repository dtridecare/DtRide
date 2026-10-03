import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// POST /functions/v1/dispatch { ride_id } — expand radius 3/5/8km, notify up to 10 drivers.
// V1: returns eligible driver ids; push via FCM in S3. Keeps free tier (no Redis).
serve(async (req) => {
  const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { ride_id } = await req.json();
  const { data: ride } = await supa.from("rides").select("*").eq("id", ride_id).single();
  if (!ride) return new Response("ride not found", { status: 404 });
  const radii = [3000, 5000, 8000];
  for (const r of radii) {
    const { data } = await supa.rpc("nearby_drivers", { p_pickup: ride.pickup, p_radius_m: r, p_category: ride.category });
    if (data?.length) return Response.json({ radius_m: r, drivers: data.slice(0, 10) });
  }
  await supa.from("rides").update({ status: "no_driver_found" }).eq("id", ride_id);
  return Response.json({ drivers: [] });
});
