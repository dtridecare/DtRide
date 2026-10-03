import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'kyc_screen.dart';
import 'profile_setup_screen.dart';

/// Branded driver auth: phone or email → OTP boxes → profile.
class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});
  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  bool _emailMode = false;
  final _id = TextEditingController();
  String _otp = '';
  bool _sent = false;
  String? _error;
  bool _busy = false;

  AuthService get _auth => AuthService(Supabase.instance.client);

  Future<void> _send() async {
    if (_id.text.trim().isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (_emailMode) {
        await _auth.sendEmailOtp(_id.text.trim());
      } else {
        await _auth.sendPhoneOtp(_id.text.trim());
      }
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
      if (_emailMode) {
        await _auth.verifyEmailOtp(_id.text.trim(), _otp);
      } else {
        await _auth.verifyPhoneOtp(_id.text.trim(), _otp);
      }
      final profile = await _auth.ensureProfile('driver');
      if (!mounted) return;
      if ((profile.fullName ?? '').isEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DriverProfileSetupScreen()));
      } else {
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
    body: Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(24, 72, 24, 32),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black87, AppColors.primaryDark],
            begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DT Ride Driver', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
          SizedBox(height: 4),
          Text(Str.driverTagline, style: TextStyle(color: Colors.white70, fontSize: 14)),
        ]),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          if (_error != null) DtBanner(kind: BannerKind.error, title: _error!),
          if (!_sent) ...[
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Phone'), icon: Icon(Icons.phone_outlined)),
                ButtonSegment(value: true, label: Text('Email'), icon: Icon(Icons.email_outlined)),
              ],
              selected: {_emailMode},
              onSelectionChanged: (s) => setState(() {
                _emailMode = s.first;
                _id.clear();
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _id,
              keyboardType: _emailMode ? TextInputType.emailAddress : TextInputType.phone,
              decoration: InputDecoration(
                hintText: _emailMode ? 'you@example.com' : Str.phoneHint,
                prefixIcon: Icon(_emailMode ? Icons.email_outlined : Icons.phone_outlined)),
            ),
            const SizedBox(height: 16),
            DtPrimaryButton(label: Str.sendOtp, busy: _busy, onPressed: _send),
          ] else ...[
            const DtSectionLabel('Enter OTP'),
            DtOtpBoxes(value: _otp, onChange: (v) => setState(() => _otp = v)),
            const SizedBox(height: 16),
            DtPrimaryButton(label: Str.verifyOtp, busy: _busy, onPressed: _verify),
            TextButton(
              onPressed: _busy ? null : () => setState(() { _sent = false; _otp = ''; }),
              child: const Text('Use a different contact'),
            ),
          ],
        ]),
      ),
    ]),
  );
}
