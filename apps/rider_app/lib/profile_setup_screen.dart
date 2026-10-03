import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'home_screen.dart';

/// First-run signup details: full name saved to the profile.
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});
  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
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
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RiderHomeScreen()));
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
          hintText: 'Full name', prefixIcon: Icon(Icons.person_outline))),
      if (_error != null) ...[
        const SizedBox(height: 8),
        DtBanner(kind: BannerKind.error, title: _error!),
      ],
      const SizedBox(height: 16),
      DtPrimaryButton(label: 'Continue', busy: _busy, onPressed: _save),
    ]),
  );
}
