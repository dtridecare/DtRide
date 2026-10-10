import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'login_screen.dart';

/// Rider profile: view + edit name, email, city. Phone is read-only.
class RiderProfileScreen extends StatefulWidget {
  const RiderProfileScreen({super.key});
  @override
  State<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends State<RiderProfileScreen> {
  DtProfile? _profile;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _city = TextEditingController();
  final _referral = TextEditingController();
  String? _myCode;
  bool _referred = false;
  String? _error;
  String? _notice;
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AuthService(Supabase.instance.client).currentProfile().then((p) {
      if (!mounted) return;
      setState(() {
        _profile = p;
        _name.text = p?.fullName ?? '';
        _email.text = p?.email ?? '';
        _city.text = p?.city ?? '';
        _loading = false;
      });
    }).catchError((e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
      return null;
    });
    final c = Supabase.instance.client;
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

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Please enter your full name.');
      return;
    }
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      final p = await AuthService(Supabase.instance.client).updateProfile(
        fullName: _name.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        city: _city.text.trim().isEmpty ? null : _city.text.trim(),
      );
      if (mounted) setState(() { _profile = p; _notice = 'Profile saved.'; });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: const BackButton(), title: const Text('Profile')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(20), children: [
            Center(
              child: CircleAvatar(
                radius: 36,
                backgroundColor: AppColors.accent,
                child: Text(
                  (_profile?.fullName ?? 'R').trim().isEmpty
                      ? 'R'
                      : _profile!.fullName!.trim().split(RegExp(r'\s+'))
                          .map((w) => w[0]).take(2).join().toUpperCase(),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.ink)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(_profile?.phone ?? '',
                  style: const TextStyle(color: AppColors.muted))),
            const SizedBox(height: 16),
            const Text('Full name', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 6),
            TextField(controller: _name,
              decoration:
                  const InputDecoration(prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 12),
            const Text('Email', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 6),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress,
              decoration:
                  const InputDecoration(prefixIcon: Icon(Icons.email_outlined))),
            const SizedBox(height: 12),
            const Text('City', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 6),
            TextField(controller: _city,
              decoration:
                  const InputDecoration(prefixIcon: Icon(Icons.location_on_outlined))),
            if (_error != null) ...[
              const SizedBox(height: 8),
              DtBanner(kind: BannerKind.error, title: _error!),
            ],
            if (_notice != null) ...[
              const SizedBox(height: 8),
              DtBanner(kind: BannerKind.success, title: _notice!),
            ],
            const SizedBox(height: 16),
            DtPrimaryButton(label: 'Save changes', busy: _busy, onPressed: _save),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Refer & earn',
                          style: TextStyle(
                              fontWeight: FontWeight.w500, fontSize: 16)),
                      const SizedBox(height: 4),
                      if (_myCode != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                              border: Border.all(
                                  style: BorderStyle.solid,
                                  color: AppColors.ink),
                              borderRadius: BorderRadius.circular(12)),
                          child: Text(_myCode!,
                              style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 3)),
                        ),
                      if (!_referred) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                              child: TextField(
                                  controller: _referral,
                                  decoration: const InputDecoration(
                                      hintText: "Friend's code"))),
                          const SizedBox(width: 8),
                          TextButton(
                              onPressed: _claim,
                              child: const Text('Apply')),
                        ]),
                      ] else
                        const Text('Referral applied.',
                            style: TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.w500)),
                    ]),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _logout,
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: AppColors.danger),
              child: const Text('Log out'),
            ),
          ]),
  );
}
