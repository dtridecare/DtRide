import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'tracking_screen.dart';

/// Past rides, newest first. Tap to reopen tracking (read-only for terminal states).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Ride> _rides = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = Supabase.instance.client.auth.currentUser!.id;
      final rows = await Supabase.instance.client
          .from('rides').select().eq('rider_id', uid)
          .order('created_at', ascending: false).limit(30);
      if (mounted) setState(() => _rides = (rows as List).map((r) => Ride.fromJson(r)).toList());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My rides')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: DtBanner(kind: BannerKind.error, title: _error!))
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _rides.isEmpty ? 1 : _rides.length,
                  itemBuilder: (context, i) {
                    if (_rides.isEmpty) {
                      return const Card(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No rides yet. Book your first trip!'),
                        ),
                      );
                    }
                    final r = _rides[i];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.directions_car)),
                        title: Text('${r.pickupText ?? '?'} → ${r.dropText ?? '?'}',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${r.status.name} · ${r.category} · ₹${r.fareEstimateRs ?? '?'}'
                          '${r.createdAt != null ? ' · ${r.createdAt!.toLocal()}'.split('.').first : ''}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TrackingScreen(ride: r))),
                      ),
                    );
                  },
                ),
              ),
  );
}
