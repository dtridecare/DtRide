import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'rider_kyc_screen.dart';

const _genders = ['Female', 'Male', 'Other'];

/// Pack signup: name, email, gender chips, referral → rider KYC.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _referral = TextEditingController();
  String? _gender;
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Please enter your full name.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final c = Supabase.instance.client;
      await AuthService(c).updateProfile(
        fullName: _name.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        gender: _gender,
      );
      final code = _referral.text.trim();
      if (code.isNotEmpty) {
        try {
          await ReferralService(c).claim(code);
        } catch (_) {}
      }
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RiderKycScreen()));
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: const BackButton(), title: const Text('')),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
      const Text('Create your profile', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
      const Text('Tell us who is riding.', style: TextStyle(color: AppColors.muted, fontSize: 14)),
      const SizedBox(height: 18),
      const Text('Full name', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 6),
      TextField(controller: _name,
        decoration: const InputDecoration(
          hintText: 'Anita Sharma', prefixIcon: Icon(Icons.person_outline))),
      const SizedBox(height: 12),
      const Text('Email (optional)', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 6),
      TextField(controller: _email, keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(
          hintText: 'name@email.com', prefixIcon: Icon(Icons.email_outlined))),
      const SizedBox(height: 12),
      const Text('Gender (optional)', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        children: [
          for (final g in _genders)
            ChoiceChip(
              label: Text(g),
              selected: _gender == g,
              onSelected: (_) => setState(() => _gender = g),
            ),
        ],
      ),
      const SizedBox(height: 12),
      const Text('Referral code (optional)', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 6),
      TextField(controller: _referral,
        decoration: const InputDecoration(
          hintText: 'Enter code', prefixIcon: Icon(Icons.card_giftcard_outlined))),
      if (_error != null) ...[
        const SizedBox(height: 8),
        DtBanner(kind: BannerKind.error, title: _error!),
      ],
      const SizedBox(height: 16),
      DtPrimaryButton(label: 'Continue to verification', busy: _busy, onPressed: _save),
    ]),
  );
}
