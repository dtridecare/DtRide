import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'kyc_screen.dart';

const _vehicleChips = [
  ('Cab', 'Mini'),
  ('Auto', 'Auto'),
  ('Bike', 'Bike'),
];

/// Pack driver signup: name, email, city, vehicle chips.
class DriverProfileSetupScreen extends StatefulWidget {
  const DriverProfileSetupScreen({super.key});
  @override
  State<DriverProfileSetupScreen> createState() => _DriverProfileSetupScreenState();
}

class _DriverProfileSetupScreenState extends State<DriverProfileSetupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _city = TextEditingController(text: 'Bengaluru');
  String _vehicle = 'Mini';
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Please enter your full name.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await AuthService(Supabase.instance.client).updateProfile(
        fullName: _name.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        city: _city.text.trim().isEmpty ? null : _city.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => KycScreen(initialCategory: _vehicle)));
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
      const Text('Create driver account',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
      const Text('Tell us about you and your vehicle.',
          style: TextStyle(color: AppColors.muted, fontSize: 14)),
      const SizedBox(height: 18),
      const Text('Full name', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 6),
      TextField(controller: _name,
        decoration: const InputDecoration(
          hintText: 'Ravi Kumar', prefixIcon: Icon(Icons.person_outline))),
      const SizedBox(height: 12),
      const Text('Email', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 6),
      TextField(controller: _email, keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(
          hintText: 'name@email.com', prefixIcon: Icon(Icons.email_outlined))),
      const SizedBox(height: 12),
      const Text('City', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 6),
      TextField(controller: _city,
        decoration: const InputDecoration(
          hintText: 'Bengaluru', prefixIcon: Icon(Icons.location_on_outlined))),
      const SizedBox(height: 12),
      const Text('Vehicle type', style: TextStyle(fontSize: 12, color: AppColors.muted)),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        children: [
          for (final chip in _vehicleChips)
            ChoiceChip(
              label: Text(chip.$1),
              selected: _vehicle == chip.$2,
              onSelected: (_) => setState(() => _vehicle = chip.$2),
            ),
        ],
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        DtBanner(kind: BannerKind.error, title: _error!),
      ],
      const SizedBox(height: 16),
      DtPrimaryButton(label: 'Continue to documents', busy: _busy, onPressed: _save),
    ]),
  );
}
