import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'booking_screen.dart';
import 'emergency_contacts_screen.dart';
import 'history_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'profile_screen.dart';
import 'rider_kyc_screen.dart';
import 'settings_screen.dart';
import 'support_screen.dart';

/// Pack home: search, Home/Work/Saved chips, recent destinations.
class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});
  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  DtProfile? _profile;
  String? _error;
  List<Ride> _recent = [];
  bool _permsOk = true;
  final _search = TextEditingController();

  // Platform announcements
  Map<String, dynamic>? _announcement;
  static const _announcementKey = '_platform_announcement';

  @override
  void initState() {
    super.initState();
    PushService(Supabase.instance.client).init();
    _checkPerms();
    _loadAnnouncements();
    final c = Supabase.instance.client;
    AuthService(c).currentProfile().then((p) {
      if (!mounted) return;
      setState(() => _profile = p);
      if (p != null && p.riderKycStatus != 'approved') {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RiderKycScreen()));
      }
    }).catchError((e) {
      if (mounted) setState(() => _error = '$e');
      return null;
    });
    c.from('rides').select().eq('rider_id', c.auth.currentUser!.id)
        .order('created_at', ascending: false).limit(3).then((rows) {
      if (mounted) {
        setState(() => _recent =
            (rows as List).map((r) => Ride.fromJson(r)).toList());
      }
    }).catchError((_) => null);
  }

  Future<void> _checkPerms() async {
    try {
      final loc = await LocationService(Supabase.instance.client).ensurePermission();
      if (!mounted) return;
      setState(() => _permsOk = loc);
    } catch (_) {}
  }

  void _loadAnnouncements() async {
    final c = Supabase.instance.client;
    try {
      final snap = await c.from('platform_announcements').select()
          .eq('target_role', 'rider')
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

  void _book([String? drop]) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => BookingScreen(initialDrop: drop)));

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    drawer: Drawer(
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              CircleAvatar(
                backgroundColor: AppColors.accent,
                child: Text(
                  ((_profile?.fullName ?? 'R').trim().isEmpty
                      ? 'R'
                      : _profile!.fullName!.trim()[0])
                      .toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.ink, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_profile?.fullName ?? 'Rider',
                        style:
                            const TextStyle(fontWeight: FontWeight.w500)),
                    Text(_profile?.phone ?? '',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ],
                ),
              ),
            ]),
          ),
          const Divider(height: 1),
        ]),
      ),
    ),
    body: SafeArea(
      child: Column(children: [
        Expanded(
          child: Stack(children: [
            Container(
              color: const Color(0xFFECEEF0),
              child: const Center(
                child:
                    Icon(Icons.map_outlined, size: 64, color: AppColors.muted)),
            ),
            Positioned(
              left: 14,
              top: 12,
              child: Builder(
                builder: (ctx) => GestureDetector(
                  onTap: () => Scaffold.of(ctx).openDrawer(),
                  child: Container(
                    height: 40,
                    width: 40,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(Icons.menu, size: 20),
                  ),
                ),
              ),
            ),
          ]),
        ),
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _announcementBanner(context),
            const Text('Where to?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => _book(),
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                    color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.search, color: AppColors.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _search.text.isEmpty ? 'Search destination' : _search.text,
                      style: const TextStyle(color: AppColors.muted)),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            if (_error != null) DtBanner(kind: BannerKind.error, title: _error!),
            if (!_permsOk)
              GestureDetector(
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(
                      builder: (ctx) => DtPermissionsScreen(
                        onDone: () {
                          Navigator.of(ctx).pop();
                          _checkPerms();
                        },
                      ),
                    ))
                    .then((_) => _checkPerms()),
                child: const DtBanner(
                  kind: BannerKind.warn,
                  title: 'Location is off — tap to enable',
                  subtitle: 'Needed for GPS pickup and live tracking.'),
              ),
            Wrap(
              spacing: 8,
              children: [
                _placeChip(Icons.home_outlined, 'Home'),
                _placeChip(Icons.work_outline, 'Work'),
                _placeChip(Icons.star_outline, 'Saved'),
              ],
            ),
            for (final r in _recent)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history, color: AppColors.muted),
                title: Text(r.dropText ?? '?',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                subtitle: Text(r.pickupText ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => _book(r.dropText),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen())),
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                label: const Text('All rides'),
              ),
            ),
          ]),
        ),
      ]),
    ),
  );

  Widget _placeChip(IconData icon, String label) => ActionChip(
    avatar: Icon(icon, size: 14),
    label: Text(label, style: const TextStyle(fontSize: 12)),
    onPressed: () => showDtMessage(context, '$label places coming soon — type or tap the map for now.'),
  );
}