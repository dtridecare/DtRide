import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

/// Server-enforced ride calls. Credits deducted in verify_otp_and_start_ride RPC.
class RideApi {
  final SupabaseClient db;
  RideApi(this.db);

  Map<String, dynamic> _single(dynamic res) {
    if (res is List) return res.first as Map<String, dynamic>;
    return res as Map<String, dynamic>;
  }

  Future<Ride> startWithOtp(String rideId, String otp) async {
    final res = await db.rpc('verify_otp_and_start_ride', params: {'p_ride': rideId, 'p_otp': otp});
    return Ride.fromJson(_single(res));
  }

  Future<Ride> complete(String rideId, double lon, double lat) async {
    final res = await db.rpc('complete_ride', params: {'p_ride': rideId, 'p_end_lon': lon, 'p_end_lat': lat});
    return Ride.fromJson(_single(res));
  }

  RealtimeChannel subscribe(String rideId, void Function(Ride) onUpdate) {
    return db.channel('ride:$rideId')
      ..onPostgresChanges(event: PostgresChangeEvent.update, schema: 'public', table: 'rides',
        filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: rideId),
        callback: (p) => onUpdate(Ride.fromJson(p.newRecord)))
      ..subscribe();
  }
}
