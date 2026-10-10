import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'login_screen.dart';

/// App settings: language (English now), alert chime, about, logout.
class RiderSettingsScreen extends StatefulWidget {
  const RiderSettingsScreen({super.key});
  @override
  State<RiderSettingsScreen> createState() => _RiderSettingsScreenState();
}

class _RiderSettingsScreenState extends State<RiderSettingsScreen> {
  String _lang = 'en';
  bool _chime = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) {
        setState(() {
          _lang = p.getString('app_lang') ?? 'en';
          _chime = p.getBool('chime_on') ?? true;
          _loading = false;
        });
      }
    });
  }

  Future<void> _set(String k, Object v) async {
    final p = await SharedPreferences.getInstance();
    if (v is bool) await p.setBool(k, v);
    if (v is String) await p.setString(k, v);
  }

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
    appBar: AppBar(leading: const BackButton(), title: const Text('Settings')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Language',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'en', label: Text('English')),
                ButtonSegment(value: 'hi', label: Text('हिन्दी')),
              ],
              selected: {_lang},
              onSelectionChanged: (s) {
                if (s.first == 'hi') {
                  showDtMessage(
                      context, 'Hindi arrives in the next update.');
                  return;
                }
                setState(() => _lang = s.first);
                _set('app_lang', s.first);
              },
            ),
            SwitchListTile(
              title: const Text('Alert chime'),
              subtitle:
                  const Text('Play the DT Ride sound on ride updates'),
              value: _chime,
              onChanged: (v) {
                setState(() => _chime = v);
                _set('chime_on', v);
              },
            ),
            const Divider(),
            const ListTile(
              title: Text('DT Ride Rider · v0.1.0'),
              subtitle: Text('Fair fares, paid directly to drivers.'),
            ),
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
