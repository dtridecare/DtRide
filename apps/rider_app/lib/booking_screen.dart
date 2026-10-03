import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dt_core/dt_core.dart';
import 'tracking_screen.dart';

/// Uber-style booking: full-screen OSM map + draggable bottom sheet.
/// Pickup/drop geocode → OSRM route + fare quote → fixed or bid request.
class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _mapCtl = MapController();
  final _pickup = TextEditingController();
  final _drop = TextEditingController();
  final _proposed = TextEditingController();
  final _coupon = TextEditingController();
  String _category = 'Mini';
  String _mode = 'fixed';
  LatLng? _from, _to, _me;
  List<LatLng> _route = [];
  FareQuote? _quote;
  int _discount = 0;
  String? _error;
  bool _busy = false;

  FareService get _fare => FareService(Supabase.instance.client);
  BookingService get _booking => BookingService(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    Geolocator.getCurrentPosition().then((p) {
      if (!mounted) return;
      setState(() {
        _me = LatLng(p.latitude, p.longitude);
        _from = _me;
        _pickup.text = 'Current location';
      });
      _mapCtl.move(_me!, 14);
    }).catchError((_) => null);
  }

  Future<void> _estimate() async {
    if (_pickup.text.trim().isEmpty || _drop.text.trim().isEmpty) {
      setState(() => _error = 'Enter pickup and drop.');
      return;
    }
    setState(() { _busy = true; _error = null; _quote = null; _discount = 0; _route = []; });
    try {
      final maps = OsmAdapter();
      final a = _from != null && _pickup.text.trim() == 'Current location'
          ? (lat: _from!.latitude, lon: _from!.longitude, label: 'Current location')
          : await maps.geocode(_pickup.text.trim());
      final b = await maps.geocode(_drop.text.trim());
      final q = await _fare.quote(
        fromLat: a.lat, fromLon: a.lon, toLat: b.lat, toLon: b.lon, category: _category);
      final r = await maps.route(a.lat, a.lon, b.lat, b.lon);
      final pts = PolylinePoints().decodePolyline(r.polyline);
      setState(() {
        _from = LatLng(a.lat, a.lon);
        _to = LatLng(b.lat, b.lon);
        _quote = q;
        _route = [for (final p in pts) LatLng(p.latitude, p.longitude)];
        _pickup.text = a.label;
        _drop.text = b.label;
      });
      _mapCtl.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds(_from!, _to!), padding: const EdgeInsets.all(80)));
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
    if (_quote == null || _from == null || _to == null) return;
    setState(() { _busy = true; _error = null; });
    try {
      final res = await _booking.createRide(
        pickupLon: _from!.longitude, pickupLat: _from!.latitude,
        dropLon: _to!.longitude, dropLat: _to!.latitude,
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
    body: Stack(children: [
      FlutterMap(
        mapController: _mapCtl,
        options: MapOptions(
          initialCenter: _me ?? const LatLng(28.6139, 77.2090),
          initialZoom: 13,
          onTap: (_, p) => setState(() {
            _to = p;
            _drop.text = '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
          }),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.dtride.rider_app',
          ),
          if (_route.isNotEmpty)
            PolylineLayer(polylines: [
              Polyline(points: _route, strokeWidth: 5, color: AppColors.primary),
            ]),
          MarkerLayer(markers: [
            if (_from != null)
              Marker(point: _from!, width: 44, height: 44,
                child: const Icon(Icons.location_pin, color: Colors.green, size: 40)),
            if (_to != null)
              Marker(point: _to!, width: 44, height: 44,
                child: const Icon(Icons.location_pin, color: Colors.red, size: 40)),
          ]),
        ],
      ),
      DraggableScrollableSheet(
        initialChildSize: 0.52, minChildSize: 0.32, maxChildSize: 0.92,
        builder: (context, scroll) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(blurRadius: 16, color: Colors.black26)],
          ),
          child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 6, 20, 24), children: [
            const DtSheetHandle(),
            Text(Str.whereTo, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(controller: _pickup,
              decoration: const InputDecoration(labelText: Str.pickupHint, prefixIcon: Icon(Icons.my_location, color: Colors.green))),
            const SizedBox(height: 8),
            TextField(controller: _drop,
              decoration: const InputDecoration(labelText: Str.dropHint, prefixIcon: Icon(Icons.place_outlined, color: Colors.red))),
            const SizedBox(height: 4),
            const Text('Tip: tap the map to drop a pin.', style: TextStyle(fontSize: 12, color: AppColors.muted)),
            const SizedBox(height: 12),
            const DtSectionLabel('Vehicle'),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: VehicleCategory.all.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final v = VehicleCategory.all[i];
                  final sel = _category == v.id;
                  return GestureDetector(
                    onTap: () => setState(() { _category = v.id; _quote = null; _discount = 0; }),
                    child: Container(
                      width: 84,
                      decoration: BoxDecoration(
                        color: sel ? AppColors.primary : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(v.icon, color: sel ? Colors.white : AppColors.ink, size: 30),
                        const SizedBox(height: 4),
                        Text(v.label, style: TextStyle(
                          color: sel ? Colors.white : AppColors.ink,
                          fontWeight: FontWeight.w700, fontSize: 12)),
                      ]),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'fixed', label: Text(Str.fixedFare), icon: Icon(Icons.tag)),
                ButtonSegment(value: 'bidding', label: Text(Str.bidFare), icon: Icon(Icons.handshake_outlined)),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            if (_mode == 'bidding') ...[
              const SizedBox(height: 8),
              TextField(controller: _proposed, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Your proposed fare ₹', prefixIcon: Icon(Icons.currency_rupee))),
            ],
            if (_quote != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.primaryDark, borderRadius: BorderRadius.circular(20)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('₹${_quote!.fareRs - _discount}',
                      style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
                  Text('${(_quote!.distanceM / 1000).toStringAsFixed(1)} km · ~${_quote!.durationS ~/ 60} min · ${Str.payDirect}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  if (_discount > 0)
                    Text('Coupon applied −₹$_discount', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: _coupon,
                  decoration: const InputDecoration(hintText: Str.couponHint))),
                const SizedBox(width: 8),
                TextButton(onPressed: _busy ? null : _applyCoupon, child: const Text(Str.apply)),
              ]),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              DtBanner(kind: BannerKind.error, title: _error!),
            ],
            const SizedBox(height: 12),
            DtPrimaryButton(label: Str.getFare, busy: _busy, onPressed: _estimate),
            if (_quote != null) ...[
              const SizedBox(height: 8),
              DtPrimaryButton(label: Str.requestRide, busy: _busy, onPressed: _request),
            ],
          ]),
        ),
      ),
    ]),
  );
}
