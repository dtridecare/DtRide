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
  final String? initialDrop;
  const BookingScreen({super.key, this.initialDrop});
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _mapCtl = MapController();
  final _pickup = TextEditingController();
  final _drop = TextEditingController();
  final _coupon = TextEditingController();
  String _category = 'Mini';
  String _mode = 'fixed';
  LatLng? _from, _to, _me;
  List<LatLng> _route = [];
  List<({String name, double lat, double lon, int radiusM})> _areas = [];
  FareQuote? _quote;
  Map<String, int> _prices = {};
  int _bid = 0;
  int _discount = 0;
  bool _pickupActive = true;
  String? _error;
  bool _busy = false;

  FareService get _fare => FareService(Supabase.instance.client);
  BookingService get _booking => BookingService(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    if (widget.initialDrop != null) _drop.text = widget.initialDrop!;
    _booking.serviceAreas().then((a) {
      if (mounted) setState(() => _areas = a);
    }).catchError((_) => null);
    LocationService(Supabase.instance.client).ensurePermission().then((ok) {
      if (!mounted) return;
      if (!ok) {
        setState(() => _error =
            'Location is off — allow access for GPS pickup, or type the address / tap the map.');
        return;
      }
      Geolocator.getCurrentPosition().then((p) {
        if (!mounted) return;
        setState(() {
          _me = LatLng(p.latitude, p.longitude);
          _from = _me;
          _pickup.text = 'Current location';
        });
        _mapCtl.move(_me!, 14);
      }).catchError((_) => null);
    });
  }

  Future<void> _useCurrent() async {
    setState(() { _busy = true; _error = null; });
    try {
      final p = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _me = LatLng(p.latitude, p.longitude);
        _from = _me;
        _pickup.text = 'Current location';
      });
      _mapCtl.move(_me!, 14);
    } catch (_) {
      setState(() => _error = 'Could not get GPS fix — allow location access or type the pickup.');
    } finally {
      setState(() => _busy = false);
    }
  }

  void _onMapTap(LatLng p) {
    setState(() {
      if (_pickupActive) {
        _from = p;
        _pickup.text = '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
      } else {
        _to = p;
        _drop.text = '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';
      }
      _quote = null;
      _discount = 0;
    });
  }

  Future<void> _estimate() async {
    if (_pickup.text.trim().isEmpty || _drop.text.trim().isEmpty) {
      setState(() => _error = 'Enter pickup and drop.');
      return;
    }
    setState(() { _busy = true; _error = null; _quote = null; _discount = 0; _route = []; });
    try {
      final maps = OsmAdapter();
      LatLng from;
      if (_from != null && (_pickup.text.trim() == 'Current location' || _isCoords(_pickup.text.trim()))) {
        from = _from!;
      } else {
        final a = await maps.geocode(_pickup.text.trim());
        from = LatLng(a.lat, a.lon);
        _pickup.text = a.label;
      }
      LatLng to;
      if (_to != null && _isCoords(_drop.text.trim())) {
        to = _to!;
      } else {
        final b = await maps.geocode(_drop.text.trim());
        to = LatLng(b.lat, b.lon);
        _drop.text = b.label;
      }
      final q = await _fare.quote(
        fromLat: from.latitude, fromLon: from.longitude,
        toLat: to.latitude, toLon: to.longitude, category: _category);
      Map<String, int> prices = {};
      try {
        prices = await _fare.quoteAll(distanceM: q.distanceM, durationS: q.durationS);
      } catch (_) {}
      // Service-area gate (server enforces too, this explains it early).
      final servedFrom = await _booking.isServed(from.longitude, from.latitude);
      final servedTo = await _booking.isServed(to.longitude, to.latitude);
      if (!servedFrom.served || !servedTo.served) {
        final cities = _areas.isEmpty
            ? 'our launch city'
            : _areas.map((a) => a.name).join(', ');
        final bad = !servedFrom.served ? 'pickup' : 'drop';
        setState(() => _error =
            'Outside service area: this $bad is not served yet. We currently serve: $cities.');
        return;
      }
      final r = await maps.route(from.latitude, from.longitude, to.latitude, to.longitude);
      final pts = PolylinePoints().decodePolyline(r.polyline);
      setState(() {
        _from = from;
        _to = to;
        _quote = q;
        _prices = prices;
        _bid = q.fareRs;
        _route = [for (final p in pts) LatLng(p.latitude, p.longitude)];
      });
      _mapCtl.fitCamera(CameraFit.bounds(
        bounds: LatLngBounds(_from!, _to!), padding: const EdgeInsets.all(80)));
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  bool _isCoords(String s) =>
      RegExp(r'^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$').hasMatch(s);

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
        proposedFare: _mode == 'bidding' ? _bid : null,
        idempotencyKey: 'r${DateTime.now().millisecondsSinceEpoch}',
      );
      if (_discount > 0 && _coupon.text.trim().isNotEmpty) {
        await CouponService(Supabase.instance.client)
            .recordUse(_coupon.text.trim(), res.ride.id);
      }
      // Fan out to nearby drivers (push + realtime). Best-effort.
      _booking.dispatchRide(res.ride.id);
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
          onTap: (_, p) => _onMapTap(p),
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.dtride.rider_app',
          ),
          if (_areas.isNotEmpty)
            CircleLayer(circles: [
              for (final a in _areas)
                CircleMarker(
                  point: LatLng(a.lat, a.lon),
                  radius: a.radiusM.toDouble(),
                  useRadiusInMeter: true,
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderColor: AppColors.primary.withValues(alpha: 0.35),
                  borderStrokeWidth: 2,
                ),
            ]),
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
              onTap: () => setState(() => _pickupActive = true),
              onChanged: (_) => _from = null,
              decoration: const InputDecoration(labelText: Str.pickupHint, prefixIcon: Icon(Icons.my_location, color: Colors.green))),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : _useCurrent,
                icon: const Icon(Icons.gps_fixed, size: 16),
                label: const Text(Str.useCurrent, style: TextStyle(fontSize: 12)),
              ),
            ),
            TextField(controller: _drop,
              onTap: () => setState(() => _pickupActive = false),
              onChanged: (_) => _to = null,
              decoration: const InputDecoration(labelText: Str.dropHint, prefixIcon: Icon(Icons.place_outlined, color: Colors.red))),
            const SizedBox(height: 4),
            Text(
              _pickupActive ? 'Tip: tap the map to set pickup.' : 'Tip: tap the map to set drop.',
              style: const TextStyle(fontSize: 12, color: AppColors.muted)),
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
            _modeSeg(),
            if (_quote != null && _mode == 'bidding') _bidBox(),
            if (_quote != null) ...[
              const SizedBox(height: 8),
              for (final v in VehicleCategory.all)
                _vehicleRow(v),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: _coupon,
                  decoration: const InputDecoration(hintText: Str.couponHint))),
                const SizedBox(width: 8),
                TextButton(onPressed: _busy ? null : _applyCoupon, child: const Text(Str.apply)),
              ]),
              if (_discount > 0)
                Text('Coupon applied −₹$_discount · you pay ₹${_quote!.fareRs - _discount}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              DtBanner(kind: BannerKind.error, title: _error!),
            ],
            const SizedBox(height: 12),
            DtPrimaryButton(label: Str.getFare, busy: _busy, onPressed: _estimate),
            if (_quote != null) ...[
              const SizedBox(height: 8),
              DtPrimaryButton(
                label: _mode == 'bidding'
                    ? 'Send offer · ₹$_bid'
                    : 'Book ${_labelOf(_category)} · ₹${_quote!.fareRs - _discount}',
                busy: _busy,
                onPressed: _request),
            ],
          ]),
        ),
      ),
    ]),
  );

  String _labelOf(String id) =>
      VehicleCategory.all.firstWhere((v) => v.id == id, orElse: () => VehicleCategory.all[2]).label;

  Widget _modeSeg() => Container(
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
    padding: const EdgeInsets.all(3),
    child: Row(children: [
      for (final m in const ['fixed', 'bidding'])
        Expanded(
          child: GestureDetector(
            onTap: () => setState(() {
              _mode = m;
              if (_quote != null) _bid = _quote!.fareRs;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: _mode == m ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: _mode == m ? Border.all(color: AppColors.border, width: 0.5) : null,
              ),
              alignment: Alignment.center,
              child: Text(m == 'fixed' ? 'Fixed fare' : 'Name your price',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            ),
          ),
        ),
    ]),
  );

  Widget _vehicleRow(VehicleCategory v) {
    final sel = _category == v.id;
    final price = _prices[v.id];
    return GestureDetector(
      onTap: () => setState(() {
        _category = v.id;
        if (_quote != null) _bid = _quote!.fareRs;
      }),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: sel ? AppColors.ink : Colors.transparent, width: sel ? 1.5 : 1),
          borderRadius: BorderRadius.circular(12),
          color: sel ? const Color(0xFFFAFAFA) : Colors.transparent,
        ),
        child: Row(children: [
          Icon(v.icon, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v.label, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text('${v.etaMin} min · ${v.seats} seat${v.seats == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.muted)),
            ]),
          ),
          if (_mode == 'bidding')
            Text('Suggested\n₹${price ?? '…'}',
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, color: AppColors.muted))
          else
            Text(price == null ? '₹…' : '₹$price',
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        ]),
      ),
    );
  }

  Widget _bidBox() {
    final base = _quote!.fareRs;
    final band = (base * 0.2).round();
    final lo = base - band, hi = base + band;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        Text('₹$_bid', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
        Text('Drivers nearby usually accept ₹$lo to ₹$hi',
            style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _stepBtn(Icons.remove, () => setState(() => _bid = (_bid - 5).clamp(lo, hi))),
          const SizedBox(width: 16),
          _stepBtn(Icons.add, () => setState(() => _bid = (_bid + 5).clamp(lo, hi))),
        ]),
      ]),
    );
  }

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
