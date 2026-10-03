import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'login_screen.dart';
import 'plans_screen.dart';
import 'requests_screen.dart';
import 'earnings_screen.dart';
import 'kyc_screen.dart';
import 'notifications_screen.dart';
import 'driver_background.dart';

/// Driver home: online toggle hero, credits ring, banners, actions.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});
  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  DriverKyc? _kyc;
  DriverSubscription? _sub;
  String? _error;
  bool _busy = false;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    PushService(Supabase.instance.client).init();
    _load();
  }

  Future<void> _load() async {
    final c = Supabase.instance.client;
    try {
      final kyc = await KycService(c).getKyc();
      final sub = await SubscriptionService(c).activeSubscription();
      final unread = await NotificationService(c).unreadCount().catchError((_) => 0);
      if (mounted) setState(() { _kyc = kyc; _sub = sub; _unread = unread; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _toggle(bool online) async {
    setState(() { _busy = true; _error = null; });
    try {
      await SubscriptionService(Supabase.instance.client).setOnline(online);
      if (online) {
        await startTrackingService();
      } else {
        await stopTrackingService();
      }
      await _load();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DriverLoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiringSoon = _sub != null &&
        _sub!.expiresAt.difference(DateTime.now()).inDays < 3;
    final lowCredits = _sub != null && _sub!.remaining <= 10;
    final progress = _sub == null || _sub!.total == 0
        ? 0.0 : (_sub!.remaining / _sub!.total).clamp(0.0, 1.0);
    return Scaffold(
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 56, 20, 88),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _kyc?.online == true ? const Color(0xFF065F46) : AppColors.primaryDark,
                _kyc?.online == true ? AppColors.success : AppColors.primary,
              ],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('DT Ride Driver',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white)),
                Text(_kyc == null ? '…' : 'KYC: ${_kyc!.kycStatus} · ${_kyc!.vehicleCategory}',
                    style: const TextStyle(color: Colors.white70)),
              ]),
            ),
            Stack(children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const NotificationsScreen()))
                    .then((_) => _load()),
              ),
              if (_unread > 0)
                Positioned(
                  right: 6, top: 6,
                  child: CircleAvatar(
                    radius: 9, backgroundColor: Colors.redAccent,
                    child: Text('$_unread', style: const TextStyle(fontSize: 11, color: Colors.white)),
                  ),
                ),
            ]),
            IconButton(icon: const Icon(Icons.logout, color: Colors.white70), onPressed: _logout),
          ]),
        ),
        Expanded(
          child: _kyc == null
              ? (_error != null
                  ? Center(child: DtBanner(kind: BannerKind.error, title: _error!))
                  : const Center(child: CircularProgressIndicator()))
              : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                  Transform.translate(
                    offset: const Offset(0, -64),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(children: [
                          SizedBox(
                            height: 84, width: 84,
                            child: Stack(alignment: Alignment.center, children: [
                              CircularProgressIndicator(
                                value: progress, strokeWidth: 9,
                                backgroundColor: Colors.grey.shade200,
                                color: lowCredits ? Colors.orange : AppColors.success),
                              Column(mainAxisSize: MainAxisSize.min, children: [
                                Text('${_sub?.remaining ?? 0}',
                                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
                                const Text('rides', style: TextStyle(fontSize: 11, color: AppColors.muted)),
                              ]),
                            ]),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(_kyc!.online ? 'You are ONLINE' : 'You are OFFLINE',
                                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                              Text(
                                _sub == null
                                    ? 'No active plan — buy one to go online.'
                                    : 'Plan expires ${_sub!.expiresAt.toLocal()}'.split('.').first,
                                style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                              const SizedBox(height: 8),
                              DtPrimaryButton(
                                label: _kyc!.online ? Str.goOffline : Str.goOnline,
                                busy: _busy,
                                onPressed: () => _toggle(!_kyc!.online),
                              ),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  if (_error != null) DtBanner(kind: BannerKind.error, title: _error!),
                  if (!_kyc!.approved)
                    DtBanner(
                      kind: BannerKind.warn,
                      title: _kyc!.kycStatus == 'rejected'
                          ? 'KYC rejected — please resubmit'
                          : 'KYC pending approval'),
                  if (!_kyc!.approved) ...[
                    const SizedBox(height: 8),
                    DtPrimaryButton(
                      label: _kyc!.kycStatus == 'rejected' ? 'Resubmit KYC' : 'Complete KYC',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const KycScreen())).then((_) => _load()),
                    ),
                  ],                  if (_kyc!.blocked)
                    DtBanner(
                      kind: BannerKind.error,
                      title: 'Blocked until ${_kyc!.blockedUntil!.toLocal()}'.split('.').first,
                      subtitle: 'Strikes: ${_kyc!.strikes}. Contact support.'),
                  if (!_kyc!.blocked && (lowCredits || expiringSoon))
                    DtBanner(
                      kind: BannerKind.warn,
                      title: lowCredits
                          ? 'Only ${_sub!.remaining} credits left'
                          : 'Plan expiring soon',
                      subtitle: 'Renew now to avoid going offline.'),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const RequestsScreen())),
                          child: const Padding(
                            padding: EdgeInsets.all(18),
                            child: Column(children: [
                              Icon(Icons.local_taxi, size: 34, color: AppColors.primary),
                              SizedBox(height: 6),
                              Text('Requests', style: TextStyle(fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Card(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const PlansScreen())),
                          child: const Padding(
                            padding: EdgeInsets.all(18),
                            child: Column(children: [
                              Icon(Icons.card_membership_outlined, size: 34, color: AppColors.primary),
                              SizedBox(height: 6),
                              Text('Plans', style: TextStyle(fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EarningsScreen())),
                    icon: const Icon(Icons.account_balance_wallet_outlined),
                    label: const Text('My earnings'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Online keeps a foreground service alive so GPS pings continue with screen off.',
                    style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
        ),
      ]),
    );
  }
}
