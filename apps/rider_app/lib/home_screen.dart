import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'booking_screen.dart';
import 'login_screen.dart';

/// Rider home (S1): profile summary. Booking map lands in S2.
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
    // Best-effort push registration (needs Firebase config files; else no-op).
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DT Ride — Rider'), actions: [
      IconButton(
        icon: const Icon(Icons.logout),
        onPressed: () async {
          await Supabase.instance.client.auth.signOut();
          if (context.mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LoginScreen()));
          }
        },
      ),
    ]),
    body: Center(
      child: _error != null
          ? Text(_error!)
          : _profile == null
              ? const CircularProgressIndicator()
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Welcome ${_profile!.phone ?? _profile!.id}'),
                  Text('Role: ${_profile!.role}'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const BookingScreen())),
                    child: const Text('Book a ride'),
                  ),
                  const SizedBox(height: 12),
                  if (_myCode != null) Text('Your referral code: $_myCode'),
                  if (!_referred)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(
                        width: 140,
                        child: TextField(controller: _referral,
                          decoration: const InputDecoration(labelText: "Friend's code")),
                      ),
                      TextButton(onPressed: _claim, child: const Text('Apply')),
                    ])
                  else
                    const Text('Referral applied ✓'),
                  if (_notice != null) Text(_notice!, style: const TextStyle(color: Colors.green)),
                ]),
    ),
  );
}
