import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';

/// Rider inbox: ride updates, credit notes, ops messages.
class RiderNotificationsScreen extends StatefulWidget {
  const RiderNotificationsScreen({super.key});
  @override
  State<RiderNotificationsScreen> createState() =>
      _RiderNotificationsScreenState();
}

class _RiderNotificationsScreenState
    extends State<RiderNotificationsScreen> {
  List<NotificationItem> _items = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items =
          await NotificationService(Supabase.instance.client).list();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead() async {
    await NotificationService(Supabase.instance.client).markAllRead();
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Notifications'),
        actions: [
          TextButton(onPressed: _markRead, child: const Text('Mark read')),
        ]),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: DtBanner(kind: BannerKind.error, title: _error!))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final n in _items)
                      Card(
                        color: n.read ? null : const Color(0xFFFFFBEB),
                        child: ListTile(
                          title: Text(n.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w500)),
                          subtitle: Text(n.body),
                          trailing: Text(
                            '${n.createdAt.toLocal()}'.split('.').first,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.muted)),
                        ),
                      ),
                    if (_items.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No notifications yet.'),
                        ),
                      ),
                  ],
                ),
              ),
  );
}
