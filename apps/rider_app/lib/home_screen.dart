import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'booking_screen.dart';
import 'history_screen.dart';
import 'login_screen.dart';

/// Rider home: greeting header, book CTA, referral card.
class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});
  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  DtProfile? _profile;
  String? _error;
  String? _notice;
  String? _myCode;
  bool _referred = false;
  final _referral = TextEditingController();

  @override
  void initState() {
    super.initState();
    PushService(Supabase.instance.client).init();
    final c = Supabase.instance.client;
    AuthService(c).currentProfile().then((p) {
      if (mounted) setState(() => _profile = p);
    }).catchError((e) {
      if (mounted) setState(() => _error = '$e');
      return null;
    });
    ReferralService(c).myCode().then((code) {
      if (mounted) setState(() => _myCode = code);
    }).catchError((_) => null);
    ReferralService(c).alreadyReferred().then((r) {
      if (mounted) setState(() => _referred = r);
    }).catchError((_) => null);
  }

  Future<void> _claim() async {
    if (_referral.text.trim().isEmpty) return;
    setState(() { _error = null; _notice = null; });
    try {
      await ReferralService(Supabase.instance.client).claim(_referral.text.trim());
      if (mounted) setState(() { _referred = true; _notice = 'Referral applied!'; });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  void _book() => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const BookingScreen()));

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 60, 20, 24),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primaryDark, AppColors.primary],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        ),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('DT Ride', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white)),
              Text(_profile == null ? '…' : 'Hi, ${_profile!.phone ?? 'rider'}',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _book,
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary),
                child: const Text('Book a ride'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HistoryScreen())),
                child: const Text('My rides', style: TextStyle(color: Colors.white70)),
              ),
            ]),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white70),
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const LoginScreen()));
              }
            },
          ),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_error != null) DtBanner(kind: BannerKind.error, title: _error!),
          if (_notice != null) DtBanner(kind: BannerKind.success, title: _notice!),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Refer & earn', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                if (_myCode != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(style: BorderStyle.solid, color: AppColors.primary),
                      borderRadius: BorderRadius.circular(12)),
                    child: Text(_myCode!,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 3)),
                  ),
                if (!_referred) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(controller: _referral,
                      decoration: const InputDecoration(hintText: "Friend's code"))),
                    const SizedBox(width: 8),
                    TextButton(onPressed: _claim, child: const Text(Str.apply)),
                  ]),
                ] else
                  const Text('Referral applied ✓', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ]),
      ),
    ]),
  );
}
