import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'login_screen.dart';
import 'plans_screen.dart';
import 'requests_screen.dart';
import 'earnings_screen.dart';
import 'kyc_screen.dart';
import 'notifications_screen.dart';
import 'driver_background.dart';

/// Pack home: mini map, rides-left pill, online toggle, day stats.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});
  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  DriverKyc? _kyc;
  DriverSubscription? _sub;
  int _todayTrips = 0;
  int _todayEarned = 0;
  String? _error;
  bool _busy = false;
  int _unread = 0;
  LatLng _me = const LatLng(28.6139, 77.2090);

  @override
  void initState() {
    super.initState();
    PushService(Supabase.instance.client).init();
    _load();
    Geolocator.getCurrentPosition().then((p) {
      if (mounted) setState(() => _me = LatLng(p.latitude, p.longitude));
    }).catchError((_) => null);
  }

  Future<void> _load() async {
    final c = Supabase.instance.client;
    try {
      final kyc = await KycService(c).getKyc();
      final sub = await SubscriptionService(c).activeSubscription();
      final unread = await NotificationService(c).unreadCount().catchError((_) => 0);
      int trips = 0, earned = 0;
      try {
        final dayAgo = DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();
        final rows = await c.from('rides').select('fare_estimate_rs')
            .eq('driver_id', c.auth.currentUser!.id)
            .eq('status', 'completed')
            .gte('completed_at', dayAgo);
        for (final r in (rows as List)) {
          trips++;
          earned += ((r as Map)['fare_estimate_rs'] ?? 0) as int;
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _kyc = kyc;
          _sub = sub;
          _unread = unread;
          _todayTrips = trips;
          _todayEarned = earned;
        });
      }
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
    final online = _kyc?.online ?? false;
    return Scaffold(
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              options: MapOptions(initialCenter: _me, initialZoom: 14,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate)),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.dtride.driver_app',
                ),
                MarkerLayer(markers: [
                  Marker(point: _me, width: 60, height: 60,
                    child: Stack(alignment: Alignment.center, children: [
                      Container(
                        height: 44, width: 44,
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.35),
                          shape: BoxShape.circle),
                      ),
                      Container(
                        height: 18, width: 18,
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.accent, width: 3)),
                      ),
                    ])),
                ]),
              ],
            ),
            Positioned(
              left: 14, top: 48,
              child: GestureDetector(
                onTap: _logout,
                child: Container(
                  height: 36, width: 36,
                  decoration: const BoxDecoration(
                      color: Colors.white, shape: BoxShape.circle),
                  child: const Icon(Icons.menu, size: 18),
                ),
              ),
            ),
            Positioned(
              right: 14, top: 48,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: AppColors.ink, borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.card_membership_outlined,
                      size: 14, color: AppColors.accent),
                  const SizedBox(width: 5),
                  Text('${_sub?.remaining ?? 0} rides left',
                      style: const TextStyle(
                          color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ]),
        ),
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: _kyc == null
              ? (_error != null
                  ? DtBanner(kind: BannerKind.error, title: _error!)
                  : const Center(child: CircularProgressIndicator()))
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(online ? "You're online" : "You're offline",
                                  style: const TextStyle(
                                      fontSize: 20, fontWeight: FontWeight.w500)),
                              Text(
                                !_kyc!.approved
                                    ? 'KYC ${ _kyc!.kycStatus} — complete it to earn'
                                    : online
                                        ? 'Looking for ride requests nearby'
                                        : 'Go online to receive requests',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.muted)),
                            ]),
                        GestureDetector(
                          onTap: _busy ? null : () => _toggle(!online),
                          child: Container(
                            width: 52, height: 30,
                            decoration: BoxDecoration(
                              color: online ? AppColors.success : Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(15)),
                            alignment:
                                online ? Alignment.centerRight : Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Container(
                              height: 24, width: 24,
                              decoration: const BoxDecoration(
                                  color: Colors.white, shape: BoxShape.circle),
                            ),
                          ),
                        ),
                      ]),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    DtBanner(kind: BannerKind.error, title: _error!),
                  ],
                  if (_kyc!.blocked) ...[
                    const SizedBox(height: 8),
                    DtBanner(
                      kind: BannerKind.error,
                      title: 'Blocked until ${_kyc!.blockedUntil!.toLocal()}'.split('.').first,
                      subtitle: 'Strikes: ${_kyc!.strikes}. Contact support.'),
                  ],
                  if (!_kyc!.approved) ...[
                    const SizedBox(height: 8),
                    DtPrimaryButton(
                      label: _kyc!.kycStatus == 'rejected' ? 'Resubmit KYC' : 'Complete KYC',
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const KycScreen())).then((_) => _load()),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      _stat('₹$_todayEarned', 'Today'),
                      _stat('$_todayTrips', 'Trips'),
                      _stat('${_sub?.remaining ?? 0}', 'Rides left'),
                    ]),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Row(children: [
                        Icon(Icons.percent_outlined,
                            size: 18, color: Color(0xFF166534)),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text('No commission. You keep every fare you earn.',
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF166534))),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: DtPrimaryButton(
                          label: 'Requests${_unread > 0 ? ' ($_unread)' : ''}',
                          onPressed: !_kyc!.online
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => const RequestsScreen())),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const EarningsScreen())),
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48)),
                          child: const Text('Earnings'),
                        ),
                      ),
                    ]),
                  ],
                ]),
        ),
      ]),
    );
  }

  Widget _stat(String value, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ]),
    ),
  );
}
