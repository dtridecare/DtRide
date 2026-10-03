import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'home_screen.dart';

/// Branded rider auth: gradient header, phone → OTP boxes.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  String _otp = '';
  bool _sent = false;
  String? _error;
  bool _busy = false;

  AuthService get _auth => AuthService(Supabase.instance.client);

  Future<void> _send() async {
    if (_phone.text.trim().isEmpty) return;
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
    if (_otp.length < 6) {
      setState(() => _error = 'Enter the OTP.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _auth.verifyPhoneOtp(_phone.text.trim(), _otp);
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
    body: Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 72, 24, 32),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [AppColors.primaryDark, AppColors.primary],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DT Ride', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white)),
          SizedBox(height: 4),
          Text(Str.riderTagline, style: TextStyle(color: Colors.white70, fontSize: 14)),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          if (_error != null) DtBanner(kind: BannerKind.error, title: _error!),
          if (!_sent) ...[
            const DtSectionLabel('Phone number'),
            TextField(controller: _phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: Str.phoneHint, prefixIcon: Icon(Icons.phone_outlined))),
            const SizedBox(height: 16),
            DtPrimaryButton(label: Str.sendOtp, busy: _busy, onPressed: _send),
          ] else ...[
            const DtSectionLabel('Enter OTP'),
            DtOtpBoxes(value: _otp, onChange: (v) => setState(() => _otp = v)),
            const SizedBox(height: 16),
            DtPrimaryButton(label: Str.verifyOtp, busy: _busy, onPressed: _verify),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _sent = false),
              child: const Text('Use a different number'),
            ),
          ],
        ]),
      ),
    ]),
  );
}
