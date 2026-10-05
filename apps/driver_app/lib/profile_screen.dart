import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'login_screen.dart';

/// Driver profile: view + edit name, email, city + vehicle summary.
class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});
  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  DtProfile? _profile;
  DriverKyc? _kyc;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _city = TextEditingController();
  String? _error;
  String? _notice;
  bool _busy = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final c = Supabase.instance.client;
    AuthService(c).currentProfile().then((p) async {
      DriverKyc? kyc;
      try {
        kyc = await KycService(c).getKyc();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _profile = p;
        _kyc = kyc;
        _name.text = p?.fullName ?? '';
        _email.text = p?.email ?? '';
        _city.text = p?.city ?? '';
        _loading = false;
      });
    }).catchError((e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
      return null;
    });
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

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const DriverLoginScreen()),
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
                  (_profile?.fullName ?? 'D').trim().isEmpty
                      ? 'D'
                      : _profile!.fullName!.trim().split(RegExp(r'\s+'))
                          .map((w) => w[0]).take(2).join().toUpperCase(),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.ink)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '${_profile?.phone ?? ''}${_kyc != null ? ' · ${_kyc!.vehicleCategory}' : ''}',
                style: const TextStyle(color: AppColors.muted))),
            if (_kyc != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('KYC: ${_kyc!.kycStatus}',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500)),
                ),
              ),
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
