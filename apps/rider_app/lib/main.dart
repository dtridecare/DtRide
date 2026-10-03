import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'login_screen.dart';
import 'home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (DtConfig.supabaseUrl.isEmpty || DtConfig.supabaseAnonKey.isEmpty) {
    runApp(const _MissingConfigApp());
    return;
  }
  await Supabase.initialize(url: DtConfig.supabaseUrl, anonKey: DtConfig.supabaseAnonKey);
  runApp(const RiderApp());
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
  const RiderApp({super.key});
  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    return MaterialApp(
      title: 'DT Ride Rider',
      theme: buildAppTheme(),
      home: session == null ? const LoginScreen() : const RiderHomeScreen(),
    );
  }
}
