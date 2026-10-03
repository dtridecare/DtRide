import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';

/// Subscription plans: list active plans, create pending order,
/// activate in test mode (allow_test_activate=true) until Razorpay keys land.
class SubscriptionService {
  final SupabaseClient db;
  SubscriptionService(this.db);

  String get _uid => db.auth.currentUser!.id;

  Future<List<SubscriptionPlan>> plans({String? category}) async {
    final rows = category == null
        ? await db.from('subscription_plans').select().eq('is_active', true).order('price_rs')
        : await db.from('subscription_plans').select().eq('is_active', true).eq('vehicle_category', category).order('price_rs');
    return (rows as List).map((r) => SubscriptionPlan.fromJson(r)).toList();
  }

  Future<DriverSubscription?> activeSubscription() async {
    final rows = await db
        .from('driver_subscriptions')
        .select()
        .eq('driver_id', _uid)
        .eq('status', 'active')
        .order('expires_at');
    final list = (rows as List).map((r) => DriverSubscription.fromJson(r)).toList();
    list.sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
    return list.isEmpty ? null : list.first;
  }

  Future<({String subscriptionId, String paymentId, int amountRs})> createOrder(String planId) async {
    final res = await db.rpc('create_subscription_order', params: {'p_plan': planId});
    final row = (res as List).first as Map<String, dynamic>;
    return (
      subscriptionId: row['subscription_id'] as String,
      paymentId: row['payment_id'] as String,
      amountRs: row['amount_rs'] as int,
    );
  }

  Future<void> activateTest(String subscriptionId) =>
      db.rpc('activate_test_subscription', params: {'p_subscription': subscriptionId});

  Future<void> setOnline(bool online, {double? lon, double? lat}) =>
      db.rpc('set_online', params: {
        'p_online': online,
        if (lon != null) 'p_lon': lon,
        if (lat != null) 'p_lat': lat,
      });
}
