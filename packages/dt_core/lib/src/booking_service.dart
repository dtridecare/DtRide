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
    final res = await db.rpc('create_ride', params: {
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
