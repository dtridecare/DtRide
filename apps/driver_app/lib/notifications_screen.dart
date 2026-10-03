import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';

/// Inbox fed by the reminders cron (low credits, expiring plans, blocks).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationItem> _items = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await NotificationService(Supabase.instance.client).list();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _markRead() async {
    await NotificationService(Supabase.instance.client).markAllRead();
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications'), actions: [
      TextButton(onPressed: _markRead, child: const Text('Mark read', style: TextStyle(color: Colors.white))),
    ]),
    body: _error != null
        ? Center(child: Text(_error!))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final n in _items)
                Card(
                  color: n.read ? null : Colors.amber.shade50,
                  child: ListTile(
                    title: Text(n.title),
                    subtitle: Text(n.body),
                    trailing: Text(n.createdAt.toLocal().toString().split('.').first,
                        style: const TextStyle(fontSize: 11)),
                  ),
                ),
              if (_items.isEmpty) const Center(child: Text('No notifications.')),
            ],
          ),
  );
}
