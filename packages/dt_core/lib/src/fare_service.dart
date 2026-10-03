import 'package:supabase_flutter/supabase_flutter.dart';
import 'maps_adapter.dart';
import 'models.dart';

/// Fare = max(min_fare, base + per_km*km + per_min*min) x surge.
/// Rates come from fare_config (admin-set), surge from app_config.
class FareService {
  final SupabaseClient db;
  final MapsAdapter maps;
  FareService(this.db, [MapsAdapter? maps]) : maps = maps ?? OsmAdapter();

  Future<FareQuote> quote({
    required double fromLat, required double fromLon,
    required double toLat, required double toLon,
    required String category,
  }) async {
    final r = await maps.route(fromLat, fromLon, toLat, toLon);
    final cfg = await db.from('fare_config').select().eq('vehicle_category', category).single();
    final surgeRow = await db.from('app_config').select('value').eq('key', 'surge_default').maybeSingle();
    final surge = double.tryParse('${surgeRow?['value'] ?? 1.0}') ?? 1.0;
    final raw = ((cfg['base_rs'] as num).toDouble() +
            (cfg['per_km_rs'] as num).toDouble() * r.distM / 1000 +
            (cfg['per_min_rs'] as num).toDouble() * r.durS / 60) *
        surge;
    final fare = raw.round().clamp(cfg['min_fare_rs'] as int, 100000);
    return FareQuote(distanceM: r.distM, durationS: r.durS, fareRs: fare);
  }
}
