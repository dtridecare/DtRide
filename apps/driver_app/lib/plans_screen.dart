import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'driver_home_screen.dart';

/// Pack plans: synced badge, active card, radio rows, pay CTA.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});
  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  List<SubscriptionPlan> _plans = [];
  DriverSubscription? _active;
  String? _selectedId;
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
    setState(() => _error = null);
    try {
      final kyc = await KycService(Supabase.instance.client).getKyc();
      final plans = await _subs.plans(category: kyc.vehicleCategory);
      final active = await _subs.activeSubscription();
      if (mounted) {
        setState(() {
          _kyc = kyc;
          _plans = plans;
          _active = active;
          _loaded = true;
          _selectedId ??= plans.isNotEmpty ? _middlePlan(plans).id : null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  SubscriptionPlan _middlePlan(List<SubscriptionPlan> plans) {
    final sorted = [...plans]..sort((a, b) => a.priceRs.compareTo(b.priceRs));
    return sorted[sorted.length ~/ 2];
  }

  bool get _popular {
    if (_plans.length < 3 || _selectedId == null) return false;
    return _selectedId == _middlePlan(_plans).id;
  }

  Future<void> _buy() async {
    final plan = _plans.where((p) => p.id == _selectedId);
    if (plan.isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final order = await _subs.createOrder(plan.first.id);
      // TODO(prod): open Razorpay checkout here with order.amountRs.
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
    final selected =
        _plans.where((p) => p.id == _selectedId).firstOrNull;
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
        const Text('Choose your plan',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE), borderRadius: BorderRadius.circular(999)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.sync, size: 12, color: Color(0xFF1E40AF)),
            SizedBox(width: 4),
            Text('Synced from admin panel',
                style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF))),
          ]),
        ),
        if (_active != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: AppColors.ink, borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Current plan · active',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w500)),
                Text('Ends ${_active!.expiresAt.toLocal()}'.split(' ').first,
                    style: const TextStyle(color: AppColors.accent, fontSize: 12)),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _active!.total == 0
                      ? 0
                      : _active!.remaining / _active!.total,
                  minHeight: 6,
                  backgroundColor: const Color(0xFF374151),
                  color: AppColors.accent),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('${_active!.remaining} of ${_active!.total} rides left',
                    style: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 12)),
              ),
            ]),
          ),
        ],
        if (_loaded && !approved)
          const DtBanner(
            kind: BannerKind.warn,
            title: 'KYC approval needed',
            subtitle: 'Plans unlock once your KYC is approved.'),
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
        const Text('Renew or switch',
            style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        for (final p in _plans)
          GestureDetector(
            onTap: () => setState(() => _selectedId = p.id),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                border: Border.all(
                  color: _selectedId == p.id
                      ? AppColors.ink
                      : AppColors.border,
                  width: _selectedId == p.id ? 1.5 : 1),
                borderRadius: BorderRadius.circular(14),
                color: _selectedId == p.id
                    ? const Color(0xFFFAFAFA)
                    : Colors.transparent,
              ),
              child: Row(children: [
                Container(
                  height: 18, width: 18,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: _selectedId == p.id
                            ? AppColors.ink
                            : const Color(0xFFD1D5DB),
                        width: _selectedId == p.id ? 5 : 2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(p.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500)),
                          if (_plans.length >= 3 &&
                              p.id == _middlePlan(_plans).id) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(999)),
                              child: const Text('Most popular',
                                  style: TextStyle(
                                      fontSize: 11, color: Color(0xFF92400E))),
                            ),
                          ],
                        ]),
                        Text(
                          '${p.rideCredits} rides · valid ${p.validityDays} days',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.muted)),
                      ]),
                ),
                Text('₹${p.priceRs}',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
              ]),
            ),
          ),
        if (_loaded && _plans.isEmpty && _error == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Text(
                    'No plans for ${_kyc?.vehicleCategory ?? 'your category'} right now.',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
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
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator())),
        const Text('No commission on rides. Keep 100% of every fare.',
            style: TextStyle(fontSize: 12, color: AppColors.muted)),
        const SizedBox(height: 12),
        DtPrimaryButton(
          label: selected == null
              ? 'Select a plan'
              : 'Buy ${selected.name} · ₹${selected.priceRs}',
          busy: _busy,
          onPressed:
              (selected == null || !approved) ? null : () => _buy(),
        ),
      ]),
    );
  }
}
