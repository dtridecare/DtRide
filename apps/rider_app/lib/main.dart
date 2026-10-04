import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (DtConfig.supabaseUrl.isEmpty || DtConfig.supabaseAnonKey.isEmpty) {
    runApp(const _MissingConfigApp());
    return;
  }
  await Supabase.initialize(url: DtConfig.supabaseUrl, anonKey: DtConfig.supabaseAnonKey);
  await DtSounds.init();
  runApp(const RiderApp());
}

class _MissingConfigApp extends StatelessWidget {  const _MissingConfigApp();
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
  Widget build(BuildContext context) => MaterialApp(
    title: 'DT Ride',
    theme: buildAppTheme(),
    home: const RiderSplash(),
  );
}
