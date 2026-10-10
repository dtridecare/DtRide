import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';

/// Driver support: disputes + tickets, new and mine.
class DriverSupportScreen extends StatefulWidget {
  const DriverSupportScreen({super.key});
  @override
  State<DriverSupportScreen> createState() => _DriverSupportScreenState();
}

class _DriverSupportScreenState extends State<DriverSupportScreen> {
  List<SupportTicket> _tickets = [];
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String? _error;
  String? _notice;
  bool _busy = false;
  bool _loading = true;

  CareService get _care => CareService(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await _care.tickets();
      if (mounted) setState(() => _tickets = t);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open() async {
    if (_subject.text.trim().isEmpty) {
      setState(() => _error = 'Give your issue a subject.');
      return;
    }
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      await _care.openTicket(subject: _subject.text, body: _body.text);
      _subject.clear();
      _body.clear();
      if (mounted) {
        setState(() => _notice = 'Ticket opened. Refund reviews take up to 24h.');
      }
      await _load();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: const BackButton(), title: const Text('Support')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(20), children: [
            const Text('New ticket or dispute',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(controller: _subject,
              decoration: const InputDecoration(
                  hintText: 'Subject (e.g. Credit refund for ride…)')),
            const SizedBox(height: 8),
            TextField(controller: _body, maxLines: 3,
              decoration: const InputDecoration(
                  hintText: 'Ride id, what happened, when…')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              DtBanner(kind: BannerKind.error, title: _error!),
            ],
            if (_notice != null) ...[
              const SizedBox(height: 8),
              DtBanner(kind: BannerKind.success, title: _notice!),
            ],
            const SizedBox(height: 12),
            DtPrimaryButton(label: 'Submit', busy: _busy, onPressed: _open),
            const SizedBox(height: 16),
            const Text('My tickets',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            for (final t in _tickets)
              Card(
                child: ListTile(
                  title: Text(t.subject,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(
                    '${t.body ?? ''}\n${t.createdAt.toLocal()}'.split('.').first,
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.status == 'resolved'
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(999)),
                    child: Text(t.status,
                        style: const TextStyle(fontSize: 11)),
                  ),
                ),
              ),
            if (_tickets.isEmpty)
              const Text('No tickets yet.',
                  style: TextStyle(color: AppColors.muted)),
          ]),
  );
}
