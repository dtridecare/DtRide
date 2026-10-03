import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'login_screen.dart';
import 'driver_home_screen.dart';
import 'kyc_screen.dart';
import 'profile_setup_screen.dart';
import 'driver_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (DtConfig.supabaseUrl.isEmpty || DtConfig.supabaseAnonKey.isEmpty) {
    runApp(const _MissingConfigApp());
    return;
  }
  await Supabase.initialize(url: DtConfig.supabaseUrl, anonKey: DtConfig.supabaseAnonKey);
  await initDriverBackground();
  final session = Supabase.instance.client.auth.currentSession;
  Widget home;
  if (session != null) {
    home = const DriverGate();
  } else {
    final seen = await OnboardingStore('driver_onboarding_seen').seen();
    home = seen ? const DriverLoginScreen() : const DriverOnboarding();
  }
  runApp(DriverApp(home: home));
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

/// Existing session: name missing → setup; KYC unapproved → KYC; else home.
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

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildAppTheme(),
    home: const Scaffold(
      body: Center(
        child: Text('Pass --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...'),
      ),
    ),
  );
}

class DriverApp extends StatelessWidget {
  final Widget home;
  const DriverApp({super.key, required this.home});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DT Ride Driver',
    theme: buildAppTheme(),
    home: home,
  );
}
