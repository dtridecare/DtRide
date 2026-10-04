import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';

/// Pack earnings: week total, 7-day bars, trip stats, recent trips.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});
  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  final List<int> _week = List.filled(7, 0);
  int _trips = 0;
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
      final weekAgo =
          DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      final trips = await db.from('rides').select('fare_estimate_rs,completed_at,mode')
          .eq('driver_id', uid).eq('status', 'completed')
          .gte('completed_at', weekAgo).order('completed_at').limit(200);
      final all = await db.from('rides').select('id')
          .eq('driver_id', uid).eq('status', 'completed').limit(1000);
      final ledger = await db.from('credit_ledger').select('delta').eq('driver_id', uid);
      final ratings = await db.from('ratings').select('stars').eq('to_id', uid);
      final recent = await db.from('rides')
          .select('fare_estimate_rs,completed_at,mode,pickup_text,drop_text')
          .eq('driver_id', uid).eq('status', 'completed')
          .order('completed_at', ascending: false).limit(10);

      final week = List.filled(7, 0);
      var collected = 0;
      for (final t in (trips as List)) {
        final m = t as Map;
        final fare = (m['fare_estimate_rs'] ?? 0) as int;
        collected += fare;
        final dt = DateTime.tryParse('${m['completed_at']}');
        if (dt != null) {
          final idx = (dt.weekday - 1).clamp(0, 6);
          week[idx] += fare;
        }
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
          _week.setAll(0, week);
          _trips = (all as List).length;
          _collected = collected;
          _creditsUsed = used;
          _avgRating = avg;
          _recent = (recent as List).cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  int _collected = 0;

  @override
  Widget build(BuildContext context) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final todayIdx = (DateTime.now().weekday - 1).clamp(0, 6);
    return Scaffold(
      appBar: AppBar(leading: const BackButton(), title: const Text('')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: DtBanner(kind: BannerKind.error, title: _error!))
              : ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('This week',
                          style: TextStyle(fontSize: 12, color: AppColors.muted)),
                      Text('₹$_collected',
                          style: const TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w500)),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: const Color(0xFFDCFCE7),
                            borderRadius: BorderRadius.circular(999)),
                        child: const Text('Commission ₹0',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF166534))),
                      ),
                      const Text('You keep 100%',
                          style:
                              TextStyle(fontSize: 12, color: AppColors.muted)),
                    ]),
                  ]),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < 7; i++)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: _WeekBar(
                                      value: _week[i],
                                      max: _week.fold<int>(
                                          1,
                                          (m, v) =>
                                              v > m ? v : m),
                                      highlight: i == todayIdx,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(days[i],
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.muted)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    _stat('$_trips', 'Trips'),
                    _stat(_avgRating == null
                        ? '—'
                        : _avgRating!.toStringAsFixed(1), 'Rating'),
                    _stat('$_creditsUsed', 'Rides used'),
                  ]),
                  const SizedBox(height: 14),
                  const Text('Recent trips',
                      style: TextStyle(fontWeight: FontWeight.w500)),
                  for (final t in _recent)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: const BoxDecoration(
                          border: Border(
                              bottom: BorderSide(
                                  color: AppColors.border, width: 0.5))),
                      child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${t['pickup_text'] ?? '?'} to ${t['drop_text'] ?? '?'}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w500)),
                                    Text(
                                      '${('${t['completed_at'] ?? ''}').split('.').first} · ${t['mode'] == 'bidding' ? 'Bid' : 'Fixed'}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.muted)),
                                  ]),
                            ),
                            Text('₹${t['fare_estimate_rs'] ?? '?'}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500)),
                          ]),
                    ),
                ]),
    );
  }

  Widget _stat(String value, String label) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text(value,
            style:
                const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ]),
    ),
  );
}

class _WeekBar extends StatelessWidget {
  final int value;
  final int max;
  final bool highlight;
  const _WeekBar(
      {required this.value, required this.max, required this.highlight});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final h = max <= 0 ? 4.0 : (value / max * c.maxHeight).clamp(4.0, c.maxHeight);
      return Container(
        decoration: BoxDecoration(
          color: highlight ? AppColors.accent : const Color(0xFFE5E7EB),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(6)),
        ),
        height: (h as num).toDouble(),
      );
    },
  );
}
