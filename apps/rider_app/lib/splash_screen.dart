import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'profile_setup_screen.dart';
import 'rider_kyc_screen.dart';

/// Rider entry: brand splash while session + onboarding state resolve.
class RiderSplash extends StatelessWidget {
  const RiderSplash({super.key});

  Future<Widget> _load() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) return const RiderGate();
    final seen = await OnboardingStore('rider_onboarding_seen').seen();
    return seen ? const LoginScreen() : const RiderOnboarding();
  }

  @override
  Widget build(BuildContext context) => BrandSplash(
    image: 'assets/branding/splash.png',
    load: _load,
  );
}

class RiderOnboarding extends StatelessWidget {
  const RiderOnboarding({super.key});
  @override
  Widget build(BuildContext context) => DtOnboarding(
    slides: const [
      OnboardSlide(
        icon: Icons.map_outlined,
        title: 'Rides across your city',
        subtitle: 'Bike, Auto, Mini, Sedan or SUV — book in seconds with live tracking.'),
      OnboardSlide(
        icon: Icons.handshake_outlined,
        title: 'Fixed fare or your bid',
        subtitle: 'Take the upfront price or propose your own like inDrive.'),
      OnboardSlide(
        icon: Icons.payments_outlined,
        title: 'Pay the driver directly',
        subtitle: 'Cash or UPI to your driver. No surge traps, no hidden cuts.'),
    ],
    cta: 'Get started',
    onDone: () async {
      await OnboardingStore('rider_onboarding_seen').markSeen();
      if (context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()));
      }
    },
  );
}

/// After login with an existing session, skip onboarding; route new
/// profiles to name setup, everyone else home.
class RiderGate extends StatefulWidget {
  const RiderGate({super.key});
  @override
  State<RiderGate> createState() => _RiderGateState();
}

class _RiderGateState extends State<RiderGate> {
  Widget _home = const Scaffold(body: Center(child: CircularProgressIndicator()));

  @override
  void initState() {
    super.initState();
    AuthService(Supabase.instance.client).currentProfile().then((p) {
      if (!mounted) return;
      Widget next;
      if (p == null) {
        next = const LoginScreen();
      } else if ((p.fullName ?? '').isEmpty) {
        next = const ProfileSetupScreen();
      } else if (p.riderKycStatus != 'approved') {
        next = const RiderKycScreen();
      } else {
        next = const RiderHomeScreen();
      }
      setState(() => _home = next);
    }).catchError((_) {
      if (mounted) setState(() => _home = const LoginScreen());
    });
  }

  @override
  Widget build(BuildContext context) => _home;
}
