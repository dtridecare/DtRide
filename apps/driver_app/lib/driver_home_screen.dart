import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'login_screen.dart';
import 'plans_screen.dart';
import 'profile_screen.dart';
import 'requests_screen.dart';
import 'earnings_screen.dart';
import 'kyc_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';
import 'driver_background.dart';

/// Pack home: mini map, rides-left pill, online toggle, day stats.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});
  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  DriverKyc? _kyc;
  DtProfile? _profile;
  DriverSubscription? _sub;
  int _todayTrips = 0;
  int _todayEarned = 0;
  String? _error;
  bool _busy = false;
  int _unread = 0;
  LatLng _me = const LatLng(28.6139, 77.2090);
  bool _permsOk = true;
  bool _bgLocOk = true;
  bool _follow = true;
  bool _satellite = false;
  final _mapCtl = MapController();
  StreamSubscription<Position>? _posSub;
  // Platform announcements
  Map<String, dynamic>? _announcement;

  @override
  void initState() {
    super.initState();
    PushService(Supabase.instance.client).init();
    _load();
    _checkPerms();
    _loadAnnouncements();
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 15),
    ).listen((p) {
      if (!mounted) return;
      setState(() => _me = LatLng(p.latitude, p.longitude));
      if (_follow) _mapCtl.move(_me, _mapCtl.camera.zoom);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _checkPerms() async {
    try {
      final locSvc = LocationService(Supabase.instance.client);
      final loc = await locSvc.ensurePermission();
      var bg = await Permission.locationAlways.status;
      if (!loc) {
        bg = PermissionStatus.denied;
      } else if (bg.isDenied) {
        bg = await Permission.locationAlways.request();
      }
      if (!mounted) return;
      setState(() {
        _permsOk = loc;
        _bgLocOk = bg.isGranted || bg.isLimited;
      });
    } catch (_) {}
  }

  Future<void> _loadAnnouncements() async {
    final c = Supabase.instance.client;
    try {
      final snap = await c.from('platform_announcements').select()
          .eq('target_role', 'driver')
          .or('target_role.eq.both')
          .expires_at_gte('now')
          .order('is_pinned', ascending: false).limit(1);
      if (mounted) {
        final ann = snap.isNotEmpty ? snap[0] : null;
        if (ann != null) {
          setState(() => _announcement = ann);
        }
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    final c = Supabase.instance.client;
    try {
      final profile = await AuthService(c).currentProfile().catchError((_) => null);
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
          _profile = profile;
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

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DriverLoginScreen()),
        (_) => false);
    }
  }

  void _openPermissions() =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (ctx) => DtPermissionsScreen(
          onDone: () {
            Navigator.of(ctx).pop();
            _checkPerms();
          },
        ),
      ));

  // Car icon animation state
  double _carIconSize = 1.0;
  late AnimationController _carAnimationCtl;
  late Animation<double> _carAnimation;

  @override
  void initState() {
    super.initState();
    PushService(Supabase.instance.client).init();
    _load();
    _checkPerms();
    _loadAnnouncements();
    _carAnimationCtl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1500)
    )..repeat(reverse: true);
    _carAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(_carAnimationCtl);
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 15),
    ).listen((p) {
      if (!mounted) return;
      setState(() => _me = LatLng(p.latitude, p.longitude));
      if (_follow) _mapCtl.move(_me, _mapCtl.camera.zoom);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _carAnimationCtl.dispose();
    super.dispose();
  }

  Future<void> _loadAnnouncements() async {
    final c = Supabase.instance.client;
    try {
      final snap = await c.from('platform_announcements').select()
          .eq('target_role', 'driver')
          .or('target_role.eq.both')
          .expires_at_gte('now')
          .order('is_pinned', ascending: false).limit(1);
      if (mounted) {
        final ann = snap.isNotEmpty ? snap[0] : null;
        if (ann != null) {
          setState(() => _announcement = ann);
        }
      }
    } catch (_) {}
  }

  Future<void> _load() async {
    final c = Supabase.instance.client;
    try {
      final profile = await AuthService(c).currentProfile().catchError((_) => null);
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
          _profile = profile;
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

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DriverLoginScreen()),
        (_) => false);
    }
  }

  void _openPermissions() =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (ctx) => DtPermissionsScreen(
          onDone: () {
            Navigator.of(ctx).pop();
            _checkPerms();
          },
        ),
      ));

  @override
  Widget build(BuildContext context) {
    final online = _kyc?.online ?? false;
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    CircleAvatar(
                      backgroundColor: AppColors.accent,
                      child: Text(
                        ((_profile?.fullName ?? 'D').trim().isEmpty
                                ? 'D'
                                : _profile!.fullName!.trim()[0])
                            .toUpperCase(),
                        style: const TextStyle(
                            color: AppColors.ink,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_profile?.fullName ?? 'Driver',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                            Text(_profile?.phone ?? '',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.muted)),
                          ]),
                    ),
                  ]),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Profile'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context)
                        .push(MaterialPageRoute(
                            builder: (_) =>
                                const DriverProfileScreen()))
                        .then((_) => _load());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Earnings'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const EarningsScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.card_membership_outlined),
                  title: const Text('Plans'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const PlansScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('Notifications'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context)
                        .push(MaterialPageRoute(
                            builder: (_) =>
                                const NotificationsScreen()))
                        .then((_) => _load());
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: const Text('Permissions'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openPermissions();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.support_agent_outlined),
                  title: const Text('Support'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const DriverSupportScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const DriverSettingsScreen()));
                  },
                ),
                const Spacer(),
                ListTile(
                  leading:
                      const Icon(Icons.logout, color: AppColors.danger),
                  title: const Text('Log out',
                      style: TextStyle(color: AppColors.danger)),
                  onTap: _logout,
                ),
              ]),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            FlutterMap(
              mapController: _mapCtl,
              options: MapOptions(
                initialCenter: _me,
                initialZoom: 14,
                interactionOptions:
                    const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                onPositionChanged: (pos, hasGesture) {
                  if (hasGesture && _follow) setState(() => _follow = false);
                },
                // Satellite mode toggle
                // Note: OpenStreetMap doesn't natively support satellite tiles without a provider,
                // but we add a layer selector for future providers. For now, we toggle map style.
                maxBounds: const LatLngBounds(
                  LatLng(10.0, 60.0),
                  LatLng(35.0, 140.0),
                ),
              ),
              children: [
                // Base tile layer - use different URL based on satellite setting
                _satellite
                    ? TileLayer(
                        urlTemplate:
                            'https://mt0.google.com/vt/lyrs=y&x={x}&y={z}&z={z}&apikey=AIzaSyB2gmelingJGJdzBImuE3tCxX4Qo6xYdl0',
                        userAgentPackageName: 'com.dtride.driver_app',
                      )
                    : TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.dtride.driver_app',
                      ),
                // Marker layer with animated car icon and profile pin
                MarkerLayer(markers: [
                  // Current location profile pin
                  Marker(
                    point: _me,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.person_outlined,
                        size: 28,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                  // Driver car icon with smooth animation
                  Marker(
                    point: _me,
                    width: 50 * _carIconSize,
                    height: 30 * _carIconSize,
                    child: AnimatedBuilder(
                      animation: _carAnimation,
                      builder: (_, __) => Transform.scale(
                        scale: _carIconSize,
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.directions_car,
                            color: Colors.white,
                            size: 24 * _carIconSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
            // Follow mode toggle
            Positioned(
              right: 14,
              top: 48,
              child: GestureDetector(
                onTap: () {
                  setState(() => _follow = true);
                  _mapCtl.move(_me, _mapCtl.camera.zoom);
                },
                child: Container(
                  height: 40,
                  width: 40,
                  decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle),
                  child: Icon(
                    _follow ? Icons.my_location : Icons.location_searching,
                    size: 20,
                  ),
                ),
              ),
            ),
            // Satellite mode toggle
            Positioned(
              left: 14,
              top: 48,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                    color: AppColors.ink, borderRadius: BorderRadius.circular(999)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.map_outlined,
                      size: 14, color: AppColors.accent),
                  const SizedBox(width: 5),
                  // Toggle text and state
                  GestureDetector(
                    onTap: () {
                      setState(() => _satellite = !_satellite);
                    },
                    child: Text(
                      _satellite ? 'Satellite' : 'Map',
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _satellite ? Icons.terrain : Icons.map,
                    size: 14,
                    color: AppColors.muted,
                  ),
                ]),
              ),
            ),
            // Rides-left pill
            Positioned(
              right: 14,
              bottom: 16,
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: _kyc == null
              ? (_error != null
                  ? DtBanner(kind: BannerKind.error, title: _error!)
                  : const Center(child: CircularProgressIndicator()))
              : Column(mainAxisSize: MainAxisSize.min, children: [
                _announcementBanner(context),
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
                if (!_permsOk) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _openPermissions,
                    child: const DtBanner(
                      kind: BannerKind.warn,
                      title: 'Location is off — tap to enable',
                      subtitle: 'Requests and tracking need GPS.'),
                  ),
                ],
                if (_permsOk && !_bgLocOk) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: _openPermissions,
                    child: const DtBanner(
                      kind: BannerKind.warn,
                      title: 'Background location off — tap to fix',
                      subtitle:
                          'Choose "Allow all the time" so trips keep tracking with the screen off.'),
                  ),
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
                    _stat('₨$_todayEarned', 'Today'),
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
                                    builder: (_) => const RequestsScreen()))),
                      ),
                    ],
                  ),
                ],
              ]),
        ),
      ]),
    );
  }

  Widget _announcementBanner(BuildContext context) => _announcement != null
      ? DtBanner(
          kind: _bannerKind(_announcement!['kind'] as String),
          title: _announcement!['title'] as String,
          subtitle: _announcement!['subtitle'] as String?,
        )
      : const SizedBox.shrink();

  BannerKind _bannerKind(String kind) => switch (kind) {
        'info' => BannerKind.info,
        'warn' => BannerKind.warn,
        'error' => BannerKind.error,
        'success' => BannerKind.success,
        _ => BannerKind.info,
      };

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