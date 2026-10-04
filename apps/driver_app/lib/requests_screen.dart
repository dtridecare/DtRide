import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'active_ride_screen.dart';

/// Pack request card: mini map, countdown, rider card, stepper, actions.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});
  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  List<NearbyRequest> _reqs = [];
  final Map<String, int> _counters = {};
  final Map<String, Map<String, dynamic>?> _parties = {};
  final Map<String, DateTime> _seenAt = {};
  String? _error;
  String? _notice;
  bool _busy = false;
  Timer? _ticker;

  BookingService get _booking => BookingService(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
    // Repaint countdown rings every second.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final pos = await Geolocator.getCurrentPosition();
      final reqs = await _booking.nearbyRequests(pos.longitude, pos.latitude);
      if (!mounted) return;
      final fresh = reqs.where((r) =>
          !_reqs.any((o) => o.rideId == r.rideId)).toList();
      setState(() => _reqs = reqs);
      for (final r in reqs) {
        _seenAt.putIfAbsent(r.rideId, () => DateTime.now());
        final base = r.mode == 'bidding'
            ? (r.proposedFare ?? r.fareEstimate)
            : r.fareEstimate;
        _counters.putIfAbsent(r.rideId, () => base);
        if (_parties[r.rideId] == null) _loadParty(r.rideId);
      }
      if (fresh.isNotEmpty) {
        DtSounds.alert(
          title: 'New ride request',
          body: '₹${fresh.first.mode == 'bidding'
              ? (fresh.first.proposedFare ?? fresh.first.fareEstimate)
              : fresh.first.fareEstimate} · ${fresh.first.category}');
      }
    } catch (e) {
      if (!mounted) return;
      final msg = '$e';
      setState(() => _error = msg.toLowerCase().contains('denied') ||
              msg.toLowerCase().contains('permission')
          ? 'Location permission needed — enable it in the Permissions screen or system Settings, then refresh.'
          : msg);
    }
  }

  Future<void> _loadParty(String rideId) async {
    try {
      final p = await Supabase.instance.client
          .rpc('ride_party_public', params: {'p_ride': rideId});
      if (mounted) {
        setState(() => _parties[rideId] = Map<String, dynamic>.from(p as Map));
      }
    } catch (_) {}
  }

  int _left(String rideId) {
    final seen = _seenAt[rideId];
    if (seen == null) return 30;
    return (30 - DateTime.now().difference(seen).inSeconds).clamp(0, 30);
  }

  Future<void> _accept(NearbyRequest r) async {
    setState(() { _busy = true; _error = null; });
    try {
      final pos = await Geolocator.getCurrentPosition();
      final ride = await _booking.acceptRide(r.rideId, pos.longitude, pos.latitude);
      _booking.notifyRide(r.rideId, 'accepted');
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => ActiveRideScreen(rideId: ride.id)));
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _offer(NearbyRequest r) async {
    final amount = _counters[r.rideId] ?? r.fareEstimate;
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      await _booking.placeOffer(r.rideId, amount);
      _booking.notifyRide(r.rideId, 'offer');
      if (mounted) {
        setState(() => _notice = 'Offer ₹$amount sent. Stay online — the rider picks fast.');
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.all(0), children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 48, 16, 0),
                  child: DtBanner(kind: BannerKind.error, title: _error!),
                ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: DtBanner(kind: BannerKind.success, title: _notice!),
                ),
              for (final r in _reqs) _card(r),
              if (_reqs.isEmpty && _error == null)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('No open requests nearby. Pull down to refresh.'),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _card(NearbyRequest r) {
    final party = _parties[r.rideId];
    final left = _left(r.rideId);
    final bidding = r.mode == 'bidding';
    final counter = _counters[r.rideId] ?? r.fareEstimate;
    final name = (party?['name'] ?? 'Rider') as String;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        SizedBox(
          height: 150,
          child: FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(r.pickupLat, r.pickupLon),
              initialZoom: 15,
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.dtride.driver_app',
              ),
              MarkerLayer(markers: [
                Marker(point: LatLng(r.pickupLat, r.pickupLon), width: 36, height: 36,
                  child: const Icon(Icons.location_pin, color: Colors.green, size: 32)),
              ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              decoration: BoxDecoration(
                  color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(children: [
                Expanded(
                  child: Text(bidding ? 'Bidding request' : 'Fixed fare',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w500,
                          color: bidding ? AppColors.ink : AppColors.muted)),
                ),
              ]),
            ),
            const SizedBox(height: 6),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Respond in 0:${left.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.surface, borderRadius: BorderRadius.circular(999)),
                child: Text('${(r.distM / 1000).toStringAsFixed(1)} km away',
                    style: const TextStyle(fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                  value: left / 30, minHeight: 4,
                  backgroundColor: AppColors.surface, color: AppColors.accent),
            ),
            const SizedBox(height: 12),
            Row(children: [
              CircleAvatar(
                backgroundColor: AppColors.accent,
                child: Text(
                  name.trim().isEmpty
                      ? 'R'
                      : name.trim().split(RegExp(r'\s+')).map((w) => w[0]).take(2).join().toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.ink, fontWeight: FontWeight.w500, fontSize: 12)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                    '${party?['rating'] ?? '—'} rating · ${party?['trips'] ?? 0} trips',
                    style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            _placeRow(Icons.circle_outlined, r.pickupText ?? '', null),
            _placeRow(Icons.crop_square_sharp, r.dropText ?? '',
                '${(r.distanceM / 1000).toStringAsFixed(1)} km'),
            const SizedBox(height: 8),
            if (bidding) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Rider offers',
                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    Text('₹${r.proposedFare ?? r.fareEstimate}',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
                  ]),
                  Row(children: [
                    _stepBtn(Icons.remove, () => setState(() {
                      _counters[r.rideId] = (counter - 5).clamp(1, 100000);
                    })),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Column(children: [
                        const Text('Your counter',
                            style: TextStyle(fontSize: 11, color: AppColors.muted)),
                        Text('₹$counter',
                            style: const TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 15)),
                      ]),
                    ),
                    _stepBtn(Icons.add, () => setState(() {
                      _counters[r.rideId] = counter + 5;
                    })),
                  ]),
                ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: DtPrimaryButton(
                      label: 'Accept ₹${r.proposedFare ?? r.fareEstimate}',
                      busy: _busy, onPressed: () => _accept(r)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DtPrimaryButton(
                      label: 'Counter ₹$counter', dark: true,
                      busy: _busy, onPressed: () => _offer(r)),
                ),
              ]),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Fixed fare',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  Text('₹${r.fareEstimate}',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500)),
                ]),
              ),
              const SizedBox(height: 8),
              DtPrimaryButton(
                label: 'Accept ₹${r.fareEstimate}',
                busy: _busy, onPressed: () => _accept(r)),
            ],
            TextButton(
              onPressed: () => setState(() {
                _reqs.removeWhere((x) => x.rideId == r.rideId);
              }),
              child: const Center(
                child: Text('Skip request',
                    style: TextStyle(color: AppColors.muted, fontSize: 13)),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _placeRow(IconData icon, String text, String? trailing) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(icon, size: 14),
      const SizedBox(width: 8),
      Expanded(
          child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
      if (trailing != null)
        Text(trailing, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
    ]),
  );

  Widget _stepBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      height: 32, width: 32,
      decoration: BoxDecoration(
          border: Border.all(color: AppColors.border), shape: BoxShape.circle),
      child: Icon(icon, size: 16),
    ),
  );
}
