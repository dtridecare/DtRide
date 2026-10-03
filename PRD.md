# DT Ride — Product Requirements Document (V1, Locked)

> 2 native Flutter apps (Rider + Driver, iOS + Android) + Next.js Admin + Supabase backend.
> Free-tier start (1000+ users), zero-rewrite upgrade to production.
> Billing: subscription credits only. No wallet, no commission. Deduct on OTP-Started.

## 1. Goals & Success Criteria

* 1-city launch, 1000+ registered users, ~50–100 concurrent rides.
* Match time p50 < 30s, OTP-start success > 95%, dispute rate < 2%.
* Host V1 ~Rs 0: Supabase Free + Vercel Free + OSM + FCM + APK/TestFlight distribution.
* Store accounts already available (Play + App Store).

## 2. Scope

### In (V1)
City rides, Airport, Rental-lite (hourly packages), vehicle categories Bike/Auto/Mini/Sedan/SUV,
auto-dispatch (fixed fare) + inDrive bidding, OTP start, live tracking, direct cash/UPI to driver,
subscription plans (admin-set price per category), KYC + admin approval, SOS/share-trip,
dual ratings, coupons/referrals (platform-funded), FCM push, support tickets.

### Out (V2)
Outstation/intercity, scheduled rides, corporate, in-app wallet/commission (schema reserved),
call masking (Exotel/Twilio), full chat, fraud ML.

## 3. Apps & Roles

| App | Users | Tech |
|---|---|---|
| Rider App | riders | Flutter, `apps/rider_app` |
| Driver App | drivers | Flutter + background location, `apps/driver_app` |
| Admin Web | ops/support | Next.js 14, `apps/admin-web` |
| Shared core | both apps | Dart package `packages/dt_core` |
| Backend | all | Supabase: Postgres 15 + PostGIS + Auth + Realtime + Storage |

Single Flutter codebase logic via `dt_core`; two store listings for independent release cycles.

## 4. Ride Lifecycle (Locked)

```
requested → accepted (30s accept timeout, auto re-queue) → arrived → started [OTP + deduct 1 credit, atomic] → completed | cancelled_after_start
```

* `requested`: rider creates request with pickup/drop, category, mode (fixed/bidding), fare estimate.
* `accepted`: first eligible driver accepts. Eligibility checked server-side: KYC approved + subscription active + credits > 0 + not expired + vehicle category match.
* `arrived`: driver within 200 m of pickup, taps Arrived.
* `started`: rider shares 4-digit OTP, driver enters it → `verify_otp_and_start_ride()` RPC verifies OTP, deducts 1 credit from active subscription, writes `credit_ledger` row. Atomic; fails if no credits.
* `completed`: driver taps End. Requires GPS proof (see §6) else flagged `suspicious`.
* `cancelled_before_otp` (by rider/driver, timeout, no-show): no deduction.
* `cancelled_after_start`: credit stays consumed. Driver cancel button disabled after start — only `Emergency End + Raise Dispute`.

OTP: 4 digits, 5 attempts max, 10-min expiry, regenerate on demand.

## 5. Matching & Dispatch

* Nearby search: PostGIS `ST_DWithin(geom, pickup, radius) + KNN order`, radii expand 3 → 5 → 8 km.
* Broadcast to up to 10 nearest eligible drivers via Realtime `geo:{geohash_cell}` + push.
* Fixed mode: first-accept wins, others get `ride_taken` event.
* Bidding mode: rider proposes fare within ±20% of estimate → drivers counter (max 3 rounds) → rider picks → converts to `accepted`. Table `ride_offers`.
* Re-queue: on timeout/reject, next batch; after 3 rounds → `no_driver_found` + retry CTA.

## 6. Anti-Scam / GPS Proof (Locked)

Because deduction happens at start, post-start evasion (fake cancel, off-book trip) is the main threat:

1. Tracking cadence: driver app sends location every 4 s while `accepted/arrived/started`.
2. End validation in `complete_ride()`:
   * `distance_m < 300 OR duration_s < 120` → `suspicious_short`
   * end point > 500 m from drop → `off_route`
   * still completes + credit stays consumed + `strikes` +1, admin review queue.
3. Mock-location detection (Android `isMockLocation`, iOS jailbreak/basic checks) → warning + flag.
4. No free cancel after start. Genuine cases (breakdown/accident) → Driver raises dispute with photo/note within 24 h → Admin refunds 1 credit (cap 3/month auto-flagged).
5. Strike policy (admin-configurable, defaults): 3 strikes / 30 days → 24 h online block.

## 7. Fare & Direct Payment

Rider pays driver 100% directly. App shows estimate + `Pay directly to driver — Cash / UPI`. Driver profile stores own UPI ID + QR.

Fare formula (per category, all admin-set):
```
fare = base + per_km × dist_km(OSRM) + per_min × eta_min + surge(area,time) + airport_fee?
```
* Surge: multiplier table by zone + time slot (e.g. 1.0–2.0x), visible before booking.
* No platform fee / GST collection in V1 (cash handling is driver-side). Columns reserved for V2 commission.

## 8. Subscription Billing (Locked — No Wallet, No Commission)

* `subscription_plans { id, name, vehicle_category, ride_credits, price_rs, validity_days, is_active }`
  Example seed: Auto 50/₹400/30d, Bike 50/₹300/30d, Mini 50/₹500/30d, Sedan 50/₹800/30d, SUV 50/₹1000/30d.
* `driver_subscriptions { id, driver_id, plan_id, credits_total, credits_used, starts_at, expires_at, status }`
* `credit_ledger { id, driver_id, subscription_id, ride_id, delta (-1 deduct / +1 refund), reason, created_at }`
* Purchase: Razorpay (UPI/cards) for plan only — low volume, stays in free tier. Webhook → activate subscription.
* Gate: `has_active_subscription(driver)` = exists row with `credits_used < credits_total AND now() < expires_at AND status='active'`. Enforced in `toggle_online`, `accept_ride`, `verify_otp_and_start_ride`.
* Reminders: FCM at 10/5/0 credits left, expiry 3 d / 1 d.
* Refunds: Admin → Disputes → Refund 1 credit (writes +1 ledger, decrements `credits_used`).
* Expiry vs exhaustion: whichever first blocks online. No grace by default (configurable `grace_rides=0`).

## 9. Auth, KYC, Safety

* Phone OTP (Supabase Auth + MSG91/Twilio) + email fallback. Rider: minimal profile. Driver: + license, RC, Aadhaar, vehicle, selfie, UPI ID → `kyc_status: pending/approved/rejected`.
* Storage buckets: `kyc-docs` (private), `avatars` (public).
* Safety: SOS button (calls + SMS emergency contacts + `sos_events` row + admin alert), share-trip link, emergency contacts CRUD.
* Ratings: dual 1–5 + tags after completion. Rider cancellation rate + driver strike rate tracked.

## 10. Admin Panel (Next.js)

Dashboard (live rides map, GMV-offline estimate, drivers online, credits sold), KYC approvals,
Plan CRUD (price/credits/validity per category), Fare/Surge config, Zone config,
Ride table + dispute/refund actions, Strikes/blocks, Coupons/referrals, Push banners, Support tickets,
Audit log. All thresholds in `app_config` table (no redeploy to tune).

## 11. Tech Stack (Frozen)

* Mobile: Flutter 3 stable, Riverpod, GoRouter, `supabase_flutter`, `flutter_map` (OSM V1) behind `MapsAdapter` → swap to `google_maps_flutter` via env, `geolocator` + background service, `firebase_messaging`, `razorpay_flutter`.
* Admin: Next.js 14 App Router + TypeScript + Tailwind + `@supabase/ssr` → Vercel.
* Backend: Supabase (Postgres + PostGIS + RLS + Realtime + Storage + Edge Functions in Deno/TypeScript).
* Realtime channels: `ride:{rideId}`, `geo:{cell}`, `driver:{driverId}`.
* CI: GitHub Actions — flutter analyze/test/build APK + next lint/build + supabase migration check.

## 12. Data Model (see `supabase/migrations/0001_init.sql`)

`profiles, drivers, vehicles, subscription_plans, driver_subscriptions, credit_ledger,
rides, ride_offers, ride_locations (partition-ready), payments (plan purchases only),
ratings, coupons, sos_events, support_tickets, app_config, audit_log`.
RLS: riders see own rides; drivers see assigned + nearby requests (via function, not raw table);
admins via `is_admin()` (checks `profiles.is_admin`). All writes to rides/credits via `SECURITY DEFINER` RPCs.

## 13. Non-Functional

* Perf: API p95 < 2 s, match fan-out < 5 s, location ingest batched, PostGIS GIST indexes.
* Scale: stateless functions, Supavisor pooling, `ride_locations` TTL/partition, upgrade path Supabase Pro → Read replicas → Redis (Upstash) for geo when > 5k concurrent.
* Security: RLS everywhere, OTP rate-limit, Razorpay webhook signature verify, PII in private buckets.
* Reliability: idempotency keys on start/complete/purchase, transactional RPCs.

## 14. Configurable Parameters (`app_config`)

`accept_timeout_s=30, search_radii_m={3000,5000,8000}, max_broadcast=10, otp_length=4, otp_attempts=5,
min_trip_m=300, min_trip_s=120, drop_geofence_m=500, strikes_limit=3, strikes_window_d=30,
block_hours=24, grace_rides=0, bidding_rounds=3, bidding_band_pct=20, location_interval_s=4`.

## 15. MVP Build Order

* S1: schema + RLS + auth + KYC + admin approve + plans CRUD + purchase (test).
* S2: booking + fare + fixed/bidding match + driver online/background GPS.
* S3: OTP-start deduct + tracking + end validation + ratings + strikes/disputes + SOS.
* S4: reminders/blocking polish + coupons + TestFlight/Play Internal + launch hardening.

## 16. Risks

OSM/OSRM accuracy vs Google (mitigated by adapter), background-GPS OEM kills (foreground service + docs),
OTP SMS cost (MSG91 free credits → own DLT), Play review for background location (declare + demo video).
