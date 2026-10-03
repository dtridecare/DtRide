import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'driver_home_screen.dart';

/// Lists active plans for the driver's category.
/// Test mode: create pending order -> activate_test_subscription.
/// Production: open Razorpay checkout with order amount, webhook activates.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  List<SubscriptionPlan> _plans = [];
  DriverSubscription? _active;
  String? _error;
  bool _busy = false;

  SubscriptionService get _subs => SubscriptionService(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final kyc = await KycService(Supabase.instance.client).getKyc();
      final plans = await _subs.plans(category: kyc.vehicleCategory);
      final active = await _subs.activeSubscription();
      if (mounted) setState(() { _plans = plans; _active = active; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _buy(SubscriptionPlan plan) async {
    setState(() { _busy = true; _error = null; });
    try {
      final order = await _subs.createOrder(plan.id);
      // TODO(prod): open Razorpay checkout here with order.amountRs.
      // Test mode activates immediately; webhook path reconciles real payments.
      await _subs.activateTest(order.subscriptionId);
      await _load();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DriverHomeScreen()));
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Subscription Plans')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (_active != null)
        Card(child: ListTile(
          title: Text('Active: ${_active!.remaining} rides left'),
          subtitle: Text('Expires ${_active!.expiresAt.toLocal()}'.split('.').first),
        )),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      for (final p in _plans)
        Card(child: ListTile(
          title: Text('${p.name} — ₹${p.priceRs}'),
          subtitle: Text('${p.rideCredits} rides · ${p.validityDays} days · ${p.category}'),
          trailing: ElevatedButton(
            onPressed: _busy ? null : () => _buy(p),
            child: const Text('Buy'),
          ),
        )),
      if (_plans.isEmpty && _error == null) const Center(child: CircularProgressIndicator()),
    ]),
  );
}
