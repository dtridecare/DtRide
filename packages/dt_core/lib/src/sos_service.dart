import 'package:supabase_flutter/supabase_flutter.dart';

/// SOS events + support disputes. Both are RPC-inserted (no direct table writes).
class SosService {
  final SupabaseClient db;
  SosService(this.db);

  Future<void> raiseSos({String? rideId, required double lon, required double lat, String? note}) =>
      db.rpc('raise_sos', params: {
        if (rideId != null) 'p_ride': rideId,
        'p_lon': lon, 'p_lat': lat,
        if (note != null) 'p_note': note,
      });

  Future<void> raiseDispute({required String rideId, required String subject, String? body}) =>
      db.rpc('raise_dispute', params: {
        'p_ride': rideId, 'p_subject': subject,
        if (body != null) 'p_body': body,
      });
}
