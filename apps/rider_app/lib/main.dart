import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'login_screen.dart';
import 'home_screen.dart';
import 'profile_setup_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (DtConfig.supabaseUrl.isEmpty || DtConfig.supabaseAnonKey.isEmpty) {
    runApp(const _MissingConfigApp());
    return;
  }
  await Supabase.initialize(url: DtConfig.supabaseUrl, anonKey: DtConfig.supabaseAnonKey);
  final session = Supabase.instance.client.auth.currentSession;
  Widget home;
  if (session != null) {
    home = const RiderGate();
  } else {
    final seen = await OnboardingStore('rider_onboarding_seen').seen();
    home = seen ? const LoginScreen() : const RiderOnboarding();
  }
  runApp(RiderApp(home: home));
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
      setState(() {
        _home = (p != null && (p.fullName ?? '').isNotEmpty)
            ? const RiderHomeScreen()
            : const ProfileSetupScreen();
      });
    }).catchError((_) {
      if (mounted) setState(() => _home = const LoginScreen());
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

class RiderApp extends StatelessWidget {
  final Widget home;
  const RiderApp({super.key, required this.home});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'DT Ride Rider',
    theme: buildAppTheme(),
    home: home,
  );
}
