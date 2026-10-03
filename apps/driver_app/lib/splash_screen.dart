import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'login_screen.dart';
import 'driver_home_screen.dart';
import 'kyc_screen.dart';
import 'profile_setup_screen.dart';

/// Entry after the brand splash: name missing → setup; KYC unapproved → KYC; else home.
class DriverGate extends StatefulWidget {
  const DriverGate({super.key});
  @override
  State<DriverGate> createState() => _DriverGateState();
}

class _DriverGateState extends State<DriverGate> {
  Widget _home = const Scaffold(body: Center(child: CircularProgressIndicator()));

  @override
  void initState() {
    super.initState();
    final c = Supabase.instance.client;
    AuthService(c).currentProfile().then((p) async {
      if (!mounted) return;
      if (p == null) {
        setState(() => _home = const DriverLoginScreen());
        return;
      }
      if ((p.fullName ?? '').isEmpty) {
        setState(() => _home = const DriverProfileSetupScreen());
        return;
      }
      try {
        final kyc = await KycService(c).getKyc();
        if (!mounted) return;
        setState(() => _home = kyc.approved
            ? const DriverHomeScreen()
            : const KycScreen());
      } catch (_) {
        if (mounted) setState(() => _home = const DriverHomeScreen());
      }
    }).catchError((_) {
      if (mounted) setState(() => _home = const DriverLoginScreen());
    });
  }

  @override
  Widget build(BuildContext context) => _home;
}

class DriverSplash extends StatelessWidget {
  const DriverSplash({super.key});

  Future<Widget> _load() async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) return const DriverGate();
    final seen = await OnboardingStore('driver_onboarding_seen').seen();
    return seen ? const DriverLoginScreen() : const DriverOnboarding();
  }

  @override
  Widget build(BuildContext context) => BrandSplash(
    image: 'assets/branding/splash.png',
    load: _load,
  );
}

class DriverOnboarding extends StatelessWidget {
  const DriverOnboarding({super.key});
  @override
  Widget build(BuildContext context) => DtOnboarding(
    slides: const [
      OnboardSlide(
        icon: Icons.payments_outlined,
        title: 'Keep 100% of every fare',
        subtitle: 'No commission. Just one flat plan — like 50 rides for ₹500.'),
      OnboardSlide(
        icon: Icons.badge_outlined,
        title: 'Quick KYC, faster payouts',
        subtitle: 'Licence, RC and UPI. Get approved and hit the road the same day.'),
      OnboardSlide(
        icon: Icons.handshake_outlined,
        title: 'Fixed fares + your bids',
        subtitle: 'Accept upfront fares or counter-offer inDrive-style.'),
    ],
    cta: 'Drive with DT Ride',
    onDone: () async {
      await OnboardingStore('driver_onboarding_seen').markSeen();
      if (context.mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const DriverLoginScreen()));
      }
    },
  );
}
