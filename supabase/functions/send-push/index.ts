// POST /functions/v1/send-push — server-only fan-out (shared secret, NOT user JWT).
// Body: { user_ids: string[], title: string, body: string, kind?: string, data?: object }
// Always writes the notifications inbox; sends FCM when FCM_SERVICE_ACCOUNT is set.
// verify_jwt MUST be false for this function (see supabase/config.toml);
// auth is the PUSH_SECRET header instead.
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function fcmToken(sa: { client_email: string; private_key: string; project_id: string }): Promise<string> {
  const pem = sa.private_key.replace(/-----.*-----/g, "").replace(/\s/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const claim = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" }))) + "." +
    b64url(new TextEncoder().encode(JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now, exp: now + 3600,
    })));
  const sig = new Uint8Array(await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(claim)));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${claim}.${b64url(sig)}`,
  });
  const j = await res.json();
  if (!j.access_token) throw new Error("fcm oauth failed");
  return j.access_token;
}

serve(async (req) => {
  const secret = Deno.env.get("PUSH_SECRET") ?? "";
  if (!secret || req.headers.get("x-push-secret") !== secret) {
    return new Response("forbidden", { status: 403 });
  }
  const { user_ids, title, body, kind = "ride", data = {} } = await req.json();
  if (!Array.isArray(user_ids) || !title) return new Response("bad request", { status: 400 });

  const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const since = new Date(Date.now() - 5 * 60e3).toISOString();
  let inbox = 0, pushed = 0;
  let token: string | null = null;
  const saRaw = Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "";

  for (const uid of user_ids) {
    // Dedupe: same user+kind+ride within 5 min.
    const rideId = (data as Record<string, unknown>).ride_id;
    let dup = false;
    if (rideId) {
      const { data: rows } = await supa.from("notifications").select("id")
        .eq("user_id", uid).eq("kind", kind).gte("created_at", since).limit(10);
      dup = (rows ?? []).length > 0;
    }
    if (!dup) {
      await supa.from("notifications").insert({ user_id: uid, title, body, kind });
      inbox++;
    }
    if (saRaw && saRaw !== "{}") {
      try {
        if (!token) token = await fcmToken(JSON.parse(saRaw));
        const sa = JSON.parse(saRaw);
        const { data: tokens } = await supa.from("push_tokens").select("token").eq("user_id", uid);
        for (const t of tokens ?? []) {
          await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
            method: "POST",
            headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
            body: JSON.stringify({
              message: {
                token: t.token,
                notification: { title, body },
                android: { notification: { sound: "dt_chime", channel_id: "dt_ride_alerts" } },
                data: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])),
              },
            }),
          });
          pushed++;
        }
      } catch (e) {
        console.log("fcm error", String(e).slice(0, 200));
      }
    }
  }
  return Response.json({ inbox, pushed });
});
