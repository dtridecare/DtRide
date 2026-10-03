import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'login_screen.dart';
import 'plans_screen.dart';
import 'requests_screen.dart';
import 'notifications_screen.dart';
import 'driver_background.dart';

/// Driver home (S1): KYC status, credits, gated online toggle.
/// set_online RPC enforces KYC-approved + active subscription + not blocked.
class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});
  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  DriverKyc? _kyc;
  DriverSubscription? _sub;
  String? _error;
  bool _busy = false;
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    PushService(Supabase.instance.client).init();
    _load();
  }

  Future<void> _load() async {
    final c = Supabase.instance.client;
    try {
      final kyc = await KycService(c).getKyc();
      final sub = await SubscriptionService(c).activeSubscription();
      final unread = await NotificationService(c).unreadCount().catchError((_) => 0);
      if (mounted) setState(() { _kyc = kyc; _sub = sub; _unread = unread; });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _toggle(bool online) async {
    setState(() { _busy = true; _error = null; });
    try {
      await SubscriptionService(Supabase.instance.client).setOnline(online);
      if (online) {
        await startTrackingService();
      } else {
        await stopTrackingService();
      }
      await _load();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final expiringSoon = _sub != null &&
        _sub!.expiresAt.difference(DateTime.now()).inDays < 3;
    final lowCredits = _sub != null && _sub!.remaining <= 10;
    return Scaffold(
    appBar: AppBar(title: const Text('DT Ride — Driver'), actions: [
      Stack(children: [
        IconButton(
          icon: const Icon(Icons.notifications),
          onPressed: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => const NotificationsScreen()))
              .then((_) => _load()),
        ),
        if (_unread > 0)
          Positioned(
            right: 6, top: 6,
            child: CircleAvatar(
              radius: 9,
              child: Text('$_unread', style: const TextStyle(fontSize: 11)),
            ),
          ),
      ]),
      IconButton(
        icon: const Icon(Icons.logout),
        onPressed: () async {
          await Supabase.instance.client.auth.signOut();
          if (context.mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const DriverLoginScreen()));
          }
        },
      ),
    ]),
    body: Padding(
      padding: const EdgeInsets.all(20),
      child: _kyc == null
          ? (_error != null ? Text(_error!) : const Center(child: CircularProgressIndicator()))
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Chip(label: Text('KYC: ${_kyc!.kycStatus}')),
              if (_kyc!.blocked)
                Card(
                  color: Colors.red.shade100,
                  child: ListTile(
                    title: Text('Blocked until ${_kyc!.blockedUntil!.toLocal()}'.split('.').first),
                    subtitle: Text('Strikes: ${_kyc!.strikes}. Contact support.'),
                  ),
                ),
              if (!(_kyc!.blocked) && (lowCredits || expiringSoon))
                Card(
                  color: Colors.amber.shade100,
                  child: ListTile(
                    title: Text(lowCredits
                        ? 'Only ${_sub!.remaining} credits left'
                        : 'Plan expires ${_sub!.expiresAt.toLocal()}'.split('.').first),
                    subtitle: const Text('Renew now to avoid going offline.'),
                  ),
                ),
              Text('Credits: ${_sub == null ? 'none — buy a plan' : '${_sub!.remaining} left, expires ${_sub!.expiresAt.toLocal()}'.split('.').first}'),
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              SwitchListTile(
                title: Text(_kyc!.online ? 'Online' : 'Offline'),
                value: _kyc!.online,
                onChanged: _busy ? null : _toggle,
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PlansScreen())),
                child: const Text('Buy / renew plan'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _kyc!.online
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const RequestsScreen()))
                    : null,
                child: const Text('View ride requests (go online first)'),
              ),
              const SizedBox(height: 8),
              const Text('Online keeps a foreground service alive so GPS pings continue with screen off.'),
            ]),
    ),
  );
  }
}
