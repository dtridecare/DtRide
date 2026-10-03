import 'package:supabase_flutter/supabase_flutter.dart';

/// Post-ride dual ratings (1-5 + tags). One per direction per ride.
class RatingService {
  final SupabaseClient db;
  RatingService(this.db);

  Future<void> submit(String rideId, int stars, [List<String> tags = const []]) =>
      db.rpc('submit_rating', params: {
        'p_ride': rideId, 'p_stars': stars, 'p_tags': tags,
      });

  Future<bool> alreadyRated(String rideId) async {
    final uid = db.auth.currentUser!.id;
    final row = await db.from('ratings').select('id')
        .eq('ride_id', rideId).eq('from_id', uid).maybeSingle();
    return row != null;
  }
}
