import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'active_ride_screen.dart';

/// Nearby open requests: fare-first cards with category icon, trip km,
/// pickup distance, accept / counter-offer.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});
  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  List<NearbyRequest> _reqs = [];
  final Map<String, TextEditingController> _offerCtrls = {};
  String? _error;
  String? _notice;
  bool _busy = false;

  BookingService get _booking => BookingService(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final pos = await Geolocator.getCurrentPosition();
      final reqs = await _booking.nearbyRequests(pos.longitude, pos.latitude);
      if (mounted) setState(() => _reqs = reqs);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  IconData _icon(String category) => VehicleCategory.all
      .firstWhere((v) => v.id == category, orElse: () => VehicleCategory.all[2]).icon;

  Future<void> _accept(NearbyRequest r) async {
    setState(() { _busy = true; _error = null; });
    try {
      final pos = await Geolocator.getCurrentPosition();
      final ride = await _booking.acceptRide(r.rideId, pos.longitude, pos.latitude);
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
    final amount = int.tryParse(_offerCtrls[r.rideId]?.text.trim() ?? '');
    if (amount == null) {
      setState(() => _error = 'Enter offer amount');
      return;
    }
    setState(() { _busy = true; _error = null; _notice = null; });
    try {
      await _booking.placeOffer(r.rideId, amount);
      if (mounted) setState(() => _notice = 'Offer ₹$amount sent. Stay online — the rider picks fast.');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ride requests'), actions: [
      IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
    ]),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null) DtBanner(kind: BannerKind.error, title: _error!),
        if (_notice != null) DtBanner(kind: BannerKind.success, title: _notice!),
        for (final r in _reqs)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(
                    backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                    child: Icon(_icon(r.category), color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('₹${r.mode == 'bidding' ? (r.proposedFare ?? r.fareEstimate) : r.fareEstimate}',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                      Text('${r.category} · ${r.mode == 'bidding' ? 'rider bid' : 'fixed fare'} · '
                          '${(r.distanceM / 1000).toStringAsFixed(1)} km trip',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)),
                    child: Text('${r.distM} m',
                        style: TextStyle(fontWeight: FontWeight.w800, color: Colors.green.shade800)),
                  ),
                ]),
                const SizedBox(height: 8),
                Text('${r.pickupText ?? ''} → ${r.dropText ?? ''}',
                    style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 12),
                if (r.mode == 'fixed')
                  DtPrimaryButton(label: 'Accept ride', busy: _busy, onPressed: () => _accept(r))
                else
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _offerCtrls.putIfAbsent(
                            r.rideId, () => TextEditingController()),
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(hintText: 'Counter ₹'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DtPrimaryButton(
                          label: 'Offer', busy: _busy, onPressed: () => _offer(r)),
                    ),
                  ]),
                ]),
              ),
            ),
        if (_reqs.isEmpty && _error == null)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('No open requests nearby. Pull down to refresh.'),
            ),
          ),
      ]),
    ),
  );
}
