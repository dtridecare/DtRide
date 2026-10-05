import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'kyc_screen.dart';
import 'profile_setup_screen.dart';

/// Pack login: logo, driver title, phone +91, yellow CTA, Google, terms.
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
  int _left = 0;

  AuthService get _auth => AuthService(Supabase.instance.client);

  Future<void> _tick() async {
    while (mounted && _left > 0) {
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) setState(() => _left--);
    }
  }

  void _goNext(DtProfile profile) {
    if (!mounted) return;
    if ((profile.fullName ?? '').isEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DriverProfileSetupScreen()));
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const KycScreen()));
    }
  }

  Future<void> _send() async {
    if (_id.text.trim().isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      if (_emailMode) {
        await _auth.sendEmailOtp(_id.text.trim());
      } else {
        await _auth.sendPhoneOtp(_id.text.trim());
      }
      setState(() {
        _sent = true;
        _left = 24;
      });
      _tick();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_otp.length < 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      if (_emailMode) {
        await _auth.verifyEmailOtp(_id.text.trim(), _otp);
      } else {
        await _auth.verifyPhoneOtp(_id.text.trim(), _otp);
      }
      _goNext(await _auth.ensureProfile('driver'));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() { _busy = true; _error = null; });
    try {
      final g = await GoogleSignIn().signIn();
      if (g == null) {
        setState(() => _busy = false);
        return;
      }
      final auth = await g.authentication;
      if (auth.idToken == null) throw StateError('no id token');
      await Supabase.instance.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: auth.idToken!,
      );
      _goNext(await _auth.ensureProfile('driver'));
    } catch (e) {
      setState(() => _error =
          'Google sign-in needs Firebase configuration — use phone or email OTP for now.');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 32, 20, 20), children: [
        const DtLogo(size: 44),
        const SizedBox(height: 22),
        const Text('Driver login', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
        const Text('Log in to start earning with DtRide.',
            style: TextStyle(color: AppColors.muted, fontSize: 14)),
        const SizedBox(height: 24),
        if (_error != null) DtBanner(kind: BannerKind.error, title: _error!),
        if (!_sent) ...[
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false,
                  label: Text('Phone'),
                  icon: Icon(Icons.phone_outlined, size: 16)),
              ButtonSegment(
                  value: true,
                  label: Text('Email'),
                  icon: Icon(Icons.email_outlined, size: 16)),
            ],
            selected: {_emailMode},
            onSelectionChanged: (s) => setState(() {
              _emailMode = s.first;
              _id.clear();
              _error = null;
            }),
          ),
          const SizedBox(height: 12),
          Text(_emailMode ? 'Email address' : 'Phone number',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 6),
          Row(children: [
            if (!_emailMode)
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: const Text('+91', style: TextStyle(fontWeight: FontWeight.w500)),
              ),
            if (!_emailMode) const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 48,
                child: TextField(
                  controller: _id,
                  keyboardType: _emailMode ? TextInputType.emailAddress : TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: _emailMode ? 'you@example.com' : '98765 43210'),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            _emailMode
                ? 'The 6-digit code arrives by email.'
                : 'The 6-digit code arrives by SMS.',
            style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          const SizedBox(height: 12),
          DtPrimaryButton(label: 'Send OTP', busy: _busy, onPressed: _send),
          const Row(children: [
            Expanded(child: Divider()),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: TextStyle(color: AppColors.muted, fontSize: 12))),
            Expanded(child: Divider()),
          ]),
          OutlinedButton.icon(
            onPressed: _busy ? null : _google,
            icon: const Icon(Icons.g_mobiledata, size: 22),
            label: const Text('Continue with Google'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          ),
          const SizedBox(height: 12),
          const Text(
            'By continuing, you agree to the Terms of Service and Privacy Policy.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 12),
          const Center(child: Text('New here? Create account',
              style: TextStyle(fontSize: 14))),
        ] else ...[
          const Text('Verify your number',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
          const Text('Enter the 6-digit code we sent you.',
              style: TextStyle(color: AppColors.muted, fontSize: 14)),
          const SizedBox(height: 16),
          DtOtpBoxes(value: _otp, onChange: (v) => setState(() => _otp = v)),
          const SizedBox(height: 8),
          Text(
            _left > 0
                ? 'Resend code in 0:${_left.toString().padLeft(2, '0')}'
                : 'You can request a new code.',
            style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 12),
          DtPrimaryButton(label: 'Verify and continue', busy: _busy, onPressed: _verify),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => setState(() { _sent = false; _otp = ''; }),
              child: const Text('Wrong number? Change',
                  style: TextStyle(color: AppColors.muted)),
            ),
          ),
        ],
      ]),
    ),
  );
}
