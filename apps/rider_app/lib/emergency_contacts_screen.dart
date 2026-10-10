import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dt_core/dt_core.dart';

/// Emergency contacts for SOS. Called from profile/drawer.
class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});
  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState
    extends State<EmergencyContactsScreen> {
  List<EmergencyContact> _items = [];
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _error;
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
      final items = await _care.contacts();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    if (_name.text.trim().isEmpty || _phone.text.trim().length < 7) {
      setState(() => _error = 'Enter a name and a valid phone number.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _care.addContact(_name.text, _phone.text);
      _name.clear();
      _phone.clear();
      await _load();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:
        AppBar(leading: const BackButton(), title: const Text('Emergency contacts')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(20), children: [
            const Text(
              'These people are one tap away during SOS, next to 112.',
              style: TextStyle(color: AppColors.muted, fontSize: 13)),
            const SizedBox(height: 12),
            for (final c in _items)
              Card(
                child: ListTile(
                  leading: const CircleAvatar(
                      child: Icon(Icons.person_outline, size: 18)),
                  title: Text(c.name,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text(c.phone),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.call_outlined),
                      onPressed: () =>
                          launchUrl(Uri.parse('tel:${c.phone}')),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.danger),
                      onPressed: () async {
                        await _care.deleteContact(c.id);
                        _load();
                      },
                    ),
                  ]),
                ),
              ),
            if (_items.isEmpty)
              const Text('No contacts yet — add at least one.',
                  style: TextStyle(color: AppColors.muted)),
            const SizedBox(height: 16),
            const Text('Add contact',
                style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            TextField(controller: _name,
              decoration: const InputDecoration(hintText: 'Name')),
            const SizedBox(height: 8),
            TextField(controller: _phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(hintText: 'Phone')),
            if (_error != null) ...[
              const SizedBox(height: 8),
              DtBanner(kind: BannerKind.error, title: _error!),
            ],
            const SizedBox(height: 12),
            DtPrimaryButton(label: 'Add contact', busy: _busy, onPressed: _add),
          ]),
  );
}
