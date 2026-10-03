import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'tracking_screen.dart';

const categories = ['Bike', 'Auto', 'Mini', 'Sedan', 'SUV'];

/// S2 booking: geocode pickup/drop -> OSRM route + fare quote -> create ride.
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _pickup = TextEditingController();
  final _drop = TextEditingController();
  final _proposed = TextEditingController();
  final _coupon = TextEditingController();
  int _discount = 0;
  String _category = 'Mini';
  String _mode = 'fixed';
  double? _fromLat, _fromLon, _toLat, _toLon;
  FareQuote? _quote;
  String? _error;
  bool _busy = false;

  FareService get _fare => FareService(Supabase.instance.client);
  BookingService get _booking => BookingService(Supabase.instance.client);

  Future<void> _estimate() async {
    setState(() { _busy = true; _error = null; _quote = null; _discount = 0; });
    try {
      final maps = OsmAdapter();
      final a = await maps.geocode(_pickup.text.trim());
      final b = await maps.geocode(_drop.text.trim());
      final q = await _fare.quote(
        fromLat: a.lat, fromLon: a.lon, toLat: b.lat, toLon: b.lon,
        category: _category);
      setState(() {
        _fromLat = a.lat; _fromLon = a.lon; _toLat = b.lat; _toLon = b.lon;
        _quote = q;
        _pickup.text = a.label;
        _drop.text = b.label;
      });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _applyCoupon() async {
    if (_quote == null || _coupon.text.trim().isEmpty) return;
    setState(() { _busy = true; _error = null; });
    try {
      final d = await CouponService(Supabase.instance.client)
          .apply(_coupon.text.trim(), _quote!.fareRs);
      if (mounted) setState(() => _discount = d);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _request() async {
    if (_quote == null || _fromLat == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final res = await _booking.createRide(
        pickupLon: _fromLon!, pickupLat: _fromLat!,
        dropLon: _toLon!, dropLat: _toLat!,
        pickupText: _pickup.text.trim(), dropText: _drop.text.trim(),
        category: _category, mode: _mode,
        distanceM: _quote!.distanceM, durationS: _quote!.durationS,
        fareEstimate: _quote!.fareRs,
        proposedFare: _mode == 'bidding' ? int.tryParse(_proposed.text.trim()) : null,
        idempotencyKey: 'r${DateTime.now().millisecondsSinceEpoch}',
      );
      if (_discount > 0 && _coupon.text.trim().isNotEmpty) {
        await CouponService(Supabase.instance.client)
            .recordUse(_coupon.text.trim(), res.ride.id);
      }
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TrackingScreen(ride: res.ride, otp: res.otp)));
      }
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Book a ride')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      TextField(controller: _pickup, decoration: const InputDecoration(labelText: 'Pickup address')),
      TextField(controller: _drop, decoration: const InputDecoration(labelText: 'Drop address')),
      DropdownButtonFormField<String>(
        initialValue: _category,
        items: [for (final c in categories) DropdownMenuItem(value: c, child: Text(c))],
        onChanged: (v) => setState(() { _category = v ?? 'Mini'; _quote = null; }),
        decoration: const InputDecoration(labelText: 'Vehicle'),
      ),
      DropdownButtonFormField<String>(
        initialValue: _mode,
        items: const [
          DropdownMenuItem(value: 'fixed', child: Text('Fixed fare (Uber-style)')),
          DropdownMenuItem(value: 'bidding', child: Text('Bid fare (inDrive-style)')),
        ],
        onChanged: (v) => setState(() => _mode = v ?? 'fixed'),
        decoration: const InputDecoration(labelText: 'Fare mode'),
      ),
      if (_mode == 'bidding')
        TextField(controller: _proposed, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Your proposed fare ₹')),
      const SizedBox(height: 12),
      if (_quote != null) ...[
        Card(child: ListTile(
          title: Text('₹${_quote!.fareRs - _discount} · ${_quote!.distanceM ~/ 1000} km'),
          subtitle: Text('~${_quote!.durationS ~/ 60} min · pay driver directly (cash/UPI)'
              '${_discount > 0 ? ' · coupon −₹$_discount' : ''}'),
        )),
        Row(children: [
          Expanded(
            child: TextField(controller: _coupon,
              decoration: const InputDecoration(labelText: 'Coupon code (optional)')),
          ),
          TextButton(onPressed: _busy ? null : _applyCoupon, child: const Text('Apply')),
        ]),
      ],
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      ElevatedButton(
        onPressed: _busy ? null : _estimate,
        child: Text(_busy ? '...' : 'Get fare estimate'),
      ),
      if (_quote != null)
        ElevatedButton(
          onPressed: _busy ? null : _request,
          child: const Text('Request ride'),
        ),
    ]),
  );
}
