import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

/// Platform-funded rider discounts. Quoted fare shown net of coupon;
/// usage recorded per ride (admin reimburses drivers off-platform in V1).
class CouponService {
  final SupabaseClient db;
  CouponService(this.db);

  Future<List<Coupon>> active() async {
    final rows = await db.from('coupons').select('code,discount_rs')
        .eq('is_active', true).order('discount_rs', ascending: false);
    return (rows as List).map((r) => Coupon.fromJson(r)).toList();
  }

  Future<int> apply(String code, int fare) async {
    final res = await db.rpc('apply_coupon', params: {'p_code': code, 'p_fare': fare});
    return (res as num).toInt();
  }

  Future<void> recordUse(String code, String rideId) async {
    try {
      await db.rpc('record_coupon_use', params: {'p_code': code, 'p_ride': rideId});
    } catch (_) {}
  }
}
