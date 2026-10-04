import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

/// Rider + driver ride lifecycle calls. All state changes enforced by RPCs.
class BookingService {
  final SupabaseClient db;
  BookingService(this.db);

  Map<String, dynamic> _single(dynamic res) {
    if (res is List) return res.first as Map<String, dynamic>;
    return res as Map<String, dynamic>;
  }

  Future<({Ride ride, String? otp})> createRide({
    required double pickupLon, required double pickupLat,
    required double dropLon, required double dropLat,
    required String pickupText, required String dropText,
    required String category, required String mode,
    required int distanceM, required int durationS, required int fareEstimate,
    int? proposedFare, String? idempotencyKey,
  }) async {
    final res = await db.rpc('request_ride', params: {
      'p_pickup_lon': pickupLon, 'p_pickup_lat': pickupLat,
      'p_drop_lon': dropLon, 'p_drop_lat': dropLat,
      'p_pickup_text': pickupText, 'p_drop_text': dropText,
      'p_category': category, 'p_mode': mode,
      'p_distance_m': distanceM, 'p_duration_s': durationS,
      'p_fare_estimate': fareEstimate,
      if (proposedFare != null) 'p_proposed_fare': proposedFare,
      if (idempotencyKey != null) 'p_idempotency': idempotencyKey,
    });
    final row = _single(res);
    final ride = await getRide(row['ride_id'] as String);
    return (ride: ride, otp: row['otp_plain'] as String?);
  }

  Future<Ride> getRide(String id) async {
    final row = await db.from('rides').select().eq('id', id).single();
    return Ride.fromJson(row);
  }

  Future<String> regenerateOtp(String rideId) async {
    final res = await db.rpc('regenerate_otp', params: {'p_ride': rideId});
    return res as String;
  }

  Future<Ride> acceptRide(String rideId, double lon, double lat) async {
    final res = await db.rpc('accept_ride',
        params: {'p_ride': rideId, 'p_lon': lon, 'p_lat': lat});
    return Ride.fromJson(_single(res));
  }

  Future<Ride> markArrived(String rideId, double lon, double lat) async {
    final res = await db.rpc('mark_arrived',
        params: {'p_ride': rideId, 'p_lon': lon, 'p_lat': lat});
    return Ride.fromJson(_single(res));
  }

  Future<Ride> cancelRide(String rideId, [String? reason]) async {
    final res = await db.rpc('cancel_ride',
        params: {'p_ride': rideId, if (reason != null) 'p_reason': reason});
    return Ride.fromJson(_single(res));
  }

  Future<RideOffer> placeOffer(String rideId, int amount) async {
    final res = await db.rpc('place_offer',
        params: {'p_ride': rideId, 'p_amount': amount});
    return RideOffer.fromJson(_single(res));
  }

  Future<Ride> acceptOffer(String rideId, String offerId) async {
    final res = await db.rpc('accept_offer',
        params: {'p_ride': rideId, 'p_offer': offerId});
    return Ride.fromJson(_single(res));
  }

  Future<List<RideOffer>> offers(String rideId) async {
    final rows = await db.from('ride_offers').select().eq('ride_id', rideId).order('created_at');
    return (rows as List).map((r) => RideOffer.fromJson(r)).toList();
  }

  Future<List<NearbyRequest>> nearbyRequests(double lon, double lat, {int radiusM = 8000}) async {
    final res = await db.rpc('nearby_requests',
        params: {'p_lon': lon, 'p_lat': lat, 'p_radius_m': radiusM});
    return (res as List).map((r) => NearbyRequest.fromJson(r)).toList();
  }

  Future<void> postLocation(String rideId, double lon, double lat, [double? speed]) =>
      db.rpc('post_location', params: {
        'p_ride': rideId, 'p_lon': lon, 'p_lat': lat,
        if (speed != null) 'p_speed': speed,
      });

  /// Ask the server to fan out this request to nearby drivers (push).
  /// Best-effort: matching still works via polling if it fails.
  Future<void> dispatchRide(String rideId) async {
    try {
      await db.functions.invoke('dispatch', body: {'ride_id': rideId});
    } catch (_) {}
  }

  /// Tell the other party about a state change (server composes + sends).
  /// Events: accepted|arrived|started|completed|cancelled|offer|offer_accepted.
  Future<void> notifyRide(String rideId, String event) async {
    try {
      await db.functions.invoke('notify-ride',
          body: {'ride_id': rideId, 'event': event});
    } catch (_) {}
  }

  /// Is a point inside a live service area? Returns area name or null.
  /// Empty RPC result (no matching area) means unserved, not an error.
  Future<({bool served, String? area})> isServed(double lon, double lat) async {
    final res = await db.rpc('is_served', params: {'p_lon': lon, 'p_lat': lat});
    if (res is List && res.isEmpty) return (served: false, area: null);
    final row = _single(res);
    return (served: (row['served'] ?? false) as bool, area: row['area_name'] as String?);
  }

  /// Active service areas (for map circles + served-city hints).
  Future<List<({String name, double lat, double lon, int radiusM})>> serviceAreas() async {
    final rows = await db.from('service_areas')
        .select('name,center,radius_m').eq('is_active', true);
    double lon = 0, lat = 0;
    final out = <({String name, double lat, double lon, int radiusM})>[];
    for (final r in (rows as List)) {
      final row = r as Map;
      final c = row['center'];
      if (c is Map && c['coordinates'] is List) {
        final coords = c['coordinates'] as List;
        lon = (coords[0] as num).toDouble();
        lat = (coords[1] as num).toDouble();
      } else if (c is String) {
        final m = RegExp(r'POINT\(([-\d.]+) ([-\d.]+)\)').firstMatch(c);
        if (m != null) {
          lon = double.parse(m.group(1)!);
          lat = double.parse(m.group(2)!);
        }
      }
      out.add((
        name: row['name'] as String? ?? '',
        lon: lon, lat: lat,
        radiusM: (row['radius_m'] ?? 0) as int,
      ));
    }
    return out;
  }

  /// Live ride updates for rider + driver tracking screens.
  RealtimeChannel watchRide(String rideId, void Function(Ride) onUpdate) {
    return db.channel('ride:$rideId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public', table: 'rides',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, column: 'id', value: rideId),
        callback: (p) => onUpdate(Ride.fromJson(p.newRecord)),
      )
      ..subscribe();
  }

  /// Live counter-offers on a bidding ride.
  RealtimeChannel watchOffers(String rideId, void Function() onChange) {
    return db.channel('offers:$rideId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public', table: 'ride_offers',
        filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq, column: 'ride_id', value: rideId),
        callback: (_) => onChange(),
      )
      ..subscribe();
  }
}
