import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';

/// Driver earnings: completed trips, fare collected (cash/UPI, off-platform),
/// credits consumed, average rider rating.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  int _trips = 0;
  int _collected = 0;
  int _creditsUsed = 0;
  double? _avgRating;
  List<Map<String, dynamic>> _recent = [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = Supabase.instance.client;
      final uid = db.auth.currentUser!.id;
      final countRes = await db.from('rides').select('id')
          .eq('driver_id', uid).eq('status', 'completed').limit(1000);
      final total = (countRes as List).length;
      final trips = await db.from('rides').select('id,fare_estimate_rs,completed_at')
          .eq('driver_id', uid).eq('status', 'completed')
          .order('completed_at', ascending: false).limit(10);
      final ledger = await db.from('credit_ledger').select('delta').eq('driver_id', uid);
      final ratings = await db.from('ratings').select('stars').eq('to_id', uid);
      var collected = 0;
      for (final t in (trips as List)) {
        collected += ((t as Map)['fare_estimate_rs'] ?? 0) as int;
      }
      var used = 0;
      for (final l in (ledger as List)) {
        if ((l as Map)['delta'] == -1) used++;
      }
      double? avg;
      if ((ratings as List).isNotEmpty) {
        var sum = 0;
        for (final r in ratings) {
          sum += ((r as Map)['stars'] ?? 0) as int;
        }
        avg = sum / ratings.length;
      }
      if (mounted) {
        setState(() {
          _trips = total;
          _collected = collected;
          _creditsUsed = used;
          _avgRating = avg;
          _recent = (trips as List).cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('My earnings')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: DtBanner(kind: BannerKind.error, title: _error!))
            : ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          Text('₹$_collected',
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                          const Text('Collected (cash/UPI)',
                              style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          Text(_avgRating == null ? '—' : _avgRating!.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                          const Text('Rider rating',
                              style: TextStyle(fontSize: 12, color: AppColors.muted)),
                        ]),
                      ),
                    ),
                  ),
                ]),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.local_taxi, color: AppColors.primary),
                    title: Text('$_trips trips completed'),
                    subtitle: Text('$_creditsUsed ride credits consumed'),
                  ),
                ),
                const DtSectionLabel('Recent trips'),
                for (final t in _recent)
                  Card(
                    child: ListTile(
                      title: Text('₹${t['fare_estimate_rs'] ?? '?'}',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${t['completed_at'] ?? ''}'.split('.').first),
                      trailing: const Icon(Icons.check_circle, color: AppColors.success),
                    ),
                  ),
              ]),
  );
}
