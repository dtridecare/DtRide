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
  DriverKyc? _kyc;
  String? _error;
  bool _busy = false;
  bool _loaded = false;

  SubscriptionService get _subs => SubscriptionService(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _error = null; });
    try {
      final kyc = await KycService(Supabase.instance.client).getKyc();
      final plans = await _subs.plans(category: kyc.vehicleCategory);
      final active = await _subs.activeSubscription();
      if (mounted) setState(() { _kyc = kyc; _plans = plans; _active = active; _loaded = true; });
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
  Widget build(BuildContext context) {
    final approved = _kyc?.approved ?? false;
    return Scaffold(
    appBar: AppBar(title: const Text('Subscription plans'), actions: [
      IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
    ]),
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
      if (_loaded && !approved) ...[
        const DtBanner(
          kind: BannerKind.warn,
          title: 'KYC approval needed',
          subtitle: 'Plans unlock once your KYC is approved. You can browse prices meanwhile.'),
      ],
      if (_error != null) ...[
        const SizedBox(height: 8),
        DtBanner(kind: BannerKind.error, title: _error!),
        TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
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
            trailing: DtPrimaryButton(
              label: 'Buy', busy: _busy,
              onPressed: approved ? () => _buy(p) : null),
          ),
        ),
      if (_loaded && _plans.isEmpty && _error == null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Text('No plans for ${_kyc?.vehicleCategory ?? 'your category'} right now.',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Text('Contact support or try again later.',
                  style: TextStyle(color: AppColors.muted)),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ]),
          ),
        ),
      if (!_loaded && _error == null)
        const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
    ]),
  );
  }
}
