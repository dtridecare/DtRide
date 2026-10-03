import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'home_screen.dart';

/// Rider phone-OTP login. Ensures a `rider` profile row on success.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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
      await _auth.ensureProfile('rider');
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
    appBar: AppBar(title: const Text('DT Ride Rider — Login')),
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
