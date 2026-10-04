import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'booking_screen.dart';
import 'history_screen.dart';
import 'login_screen.dart';
import 'rider_kyc_screen.dart';

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
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    PushService(Supabase.instance.client).init();
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

  void _book([String? drop]) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => BookingScreen(initialDrop: drop)));

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(children: [
        Expanded(
          child: Container(
            color: const Color(0xFFECEEF0),
            child: const Center(
              child: Icon(Icons.map_outlined, size: 64, color: AppColors.muted)),
          ),
        ),
        Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                ]),
              ),
            ),
            const SizedBox(height: 8),
            if (_error != null) DtBanner(kind: BannerKind.error, title: _error!),
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
