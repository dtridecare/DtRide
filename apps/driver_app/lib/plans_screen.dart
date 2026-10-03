import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'driver_home_screen.dart';

/// Plans by category with active-plan progress. Test mode activates
/// immediately; production opens Razorpay (see TODO) with webhook activation.
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
    appBar: AppBar(title: const Text('Subscription plans')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (_active != null)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryDark, AppColors.primary]),
            borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('ACTIVE PLAN', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
            Text('${_active!.remaining} rides left',
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _active!.total == 0 ? 0 : _active!.remaining / _active!.total,
                minHeight: 8, backgroundColor: Colors.white24, color: Colors.white),
            ),
            const SizedBox(height: 4),
            Text('Expires ${_active!.expiresAt.toLocal()}'.split('.').first,
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        DtBanner(kind: BannerKind.error, title: _error!),
      ],
      const SizedBox(height: 12),
      const DtSectionLabel('Available plans'),
      for (final p in _plans)
        Card(
          child: ListTile(
            leading: const CircleAvatar(child: Icon(Icons.card_membership_outlined)),
            title: Text('${p.name} — ₹${p.priceRs}',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('${p.rideCredits} rides · ${p.validityDays} days · ₹${(p.priceRs / p.rideCredits).toStringAsFixed(1)}/ride'),
            trailing: DtPrimaryButton(label: 'Buy', busy: _busy, onPressed: () => _buy(p)),
          ),
        ),
      if (_plans.isEmpty && _error == null)
        const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
    ]),
  );
}
