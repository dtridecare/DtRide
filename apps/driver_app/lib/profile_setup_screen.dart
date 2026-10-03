import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'kyc_screen.dart';

/// First-run signup details for drivers, then into KYC.
class DriverProfileSetupScreen extends StatefulWidget {
  const DriverProfileSetupScreen({super.key});
  @override
  State<DriverProfileSetupScreen> createState() => _DriverProfileSetupScreenState();
}

class _DriverProfileSetupScreenState extends State<DriverProfileSetupScreen> {
  final _name = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = 'Please enter your full name.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await AuthService(Supabase.instance.client)
          .updateProfile(fullName: _name.text.trim());
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (ctx) => DtPermissionsScreen(
            onDone: () => Navigator.of(ctx).pushReplacement(
              MaterialPageRoute(builder: (_) => const KycScreen())),
          ),
        ));
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Complete signup')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      const DtSectionLabel('Your name'),
      TextField(controller: _name,
        decoration: const InputDecoration(
          hintText: 'Full name (as on licence)', prefixIcon: Icon(Icons.person_outline))),
      if (_error != null) ...[
        const SizedBox(height: 8),
        DtBanner(kind: BannerKind.error, title: _error!),
      ],
      const SizedBox(height: 16),
      DtPrimaryButton(label: 'Continue to vehicle KYC', busy: _busy, onPressed: _save),
    ]),
  );
}
