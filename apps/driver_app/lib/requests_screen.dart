import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'active_ride_screen.dart';

/// Nearby open requests for this driver's category.
/// Fixed -> Accept (first-wins claim). Bidding -> counter-offer within band.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key});
  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  List<NearbyRequest> _reqs = [];
  final Map<String, TextEditingController> _offerCtrls = {};
  String? _error;
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
    setState(() { _busy = true; _error = null; });
    try {
      await _booking.placeOffer(r.rideId, amount);
      if (mounted) setState(() => _error = 'Offer ₹$amount sent. Wait for rider to accept.');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nearby requests'), actions: [
      IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
    ]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      for (final r in _reqs)
        Card(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r.category} · ${r.mode} · ${r.distM} m away',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${r.pickupText ?? ''} → ${r.dropText ?? ''}'),
            Text('Trip ~${r.distanceM ~/ 1000} km · Est ₹${r.fareEstimate}'
                '${r.mode == 'bidding' ? ' · rider bid ₹${r.proposedFare}' : ''}'),
            const SizedBox(height: 8),
            if (r.mode == 'fixed')
              ElevatedButton(
                onPressed: _busy ? null : () => _accept(r),
                child: const Text('Accept'),
              )
            else
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _offerCtrls.putIfAbsent(
                        r.rideId, () => TextEditingController()),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Counter ₹'),
                  ),
                ),
                ElevatedButton(
                  onPressed: _busy ? null : () => _offer(r),
                  child: const Text('Offer'),
                ),
              ]),
          ]),
        )),
      if (_reqs.isEmpty && _error == null)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: Text('No open requests nearby. Pull to refresh.')),
        ),
    ]),
  );
}
