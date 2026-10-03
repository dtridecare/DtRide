import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'kyc_screen.dart';

/// Driver phone-OTP login. Ensures a `driver` profile + driver row on success.
class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});
  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  final _phone = TextEditingController();
  final _otp = TextEditingController();
  bool _sent = false;
  String? _error;
  bool _busy = false;

  AuthService get _auth => AuthService(Supabase.instance.client);

  Future<void> _send() async {
    setState(() { _busy = true; _error = null; });
    try {
      await _auth.sendPhoneOtp(_phone.text.trim());
      setState(() => _sent = true);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() { _busy = true; _error = null; });
    try {
      await _auth.verifyPhoneOtp(_phone.text.trim(), _otp.text.trim());
      await _auth.ensureProfile('driver');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const KycScreen()));
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('DT Ride Driver — Login')),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        TextField(controller: _phone, keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone (+91...)')),
        if (_sent)
          TextField(controller: _otp, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'OTP')),
        const SizedBox(height: 16),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        ElevatedButton(
          onPressed: _busy ? null : (_sent ? _verify : _send),
          child: Text(_busy ? '...' : (_sent ? 'Verify OTP' : 'Send OTP')),
        ),
      ]),
    ),
  );
}
