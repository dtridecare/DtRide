import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dt_core/dt_core.dart';

const _ratingTags = ['Polite', 'Clean car', 'Safe driving', 'On time', 'Rash driving', 'Overcharged'];

/// Live ride status for the rider: OTP to share, driver assignment,
/// counter-offers in bidding mode, cancel before OTP.
class TrackingScreen extends StatefulWidget {
  final Ride ride;
  final String? otp;
  const TrackingScreen({super.key, required this.ride, this.otp});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  late Ride _ride;
  String? _otp;
  List<RideOffer> _offers = [];
  String? _error;
  String? _notice;
  RealtimeChannel? _rideCh;
  RealtimeChannel? _offerCh;
  int _stars = 5;
  final Set<String> _tags = {};
  bool _rated = false;

  BookingService get _booking => BookingService(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _ride = widget.ride;
    _otp = widget.otp;
    final svc = _booking;
    _rideCh = svc.watchRide(_ride.id, (r) {
      if (mounted) {
        setState(() => _ride = r);
        if (r.status == RideStatus.completed) _checkRated();
      }
    });
    if (_ride.mode == 'bidding') {
      _offerCh = svc.watchOffers(_ride.id, _loadOffers);
      _loadOffers();
    }
    if (_ride.status == RideStatus.completed) _checkRated();
    PushService(Supabase.instance.client).subscribeRide(_ride.id);
  }

  Future<void> _loadOffers() async {
    try {
      final offers = await _booking.offers(_ride.id);
      if (mounted) setState(() => _offers = offers);
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_rideCh != null) Supabase.instance.client.removeChannel(_rideCh!);
    if (_offerCh != null) Supabase.instance.client.removeChannel(_offerCh!);
    super.dispose();
  }

  Future<void> _acceptOffer(RideOffer o) async {
    setState(() => _error = null);
    try {
      final r = await _booking.acceptOffer(_ride.id, o.id);
      if (mounted) setState(() => _ride = r);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _checkRated() async {
    try {
      final done = await RatingService(Supabase.instance.client).alreadyRated(_ride.id);
      if (mounted) setState(() => _rated = done);
    } catch (_) {}
  }

  Future<void> _regenOtp() async {
    setState(() { _error = null; _notice = null; });
    try {
      final otp = await _booking.regenerateOtp(_ride.id);
      if (mounted) setState(() { _otp = otp; _notice = 'New OTP generated'; });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _sos() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Emergency SOS?'),
        content: const Text('This alerts DT Ride support with your live location.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('SEND SOS')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final pos = await Geolocator.getCurrentPosition();
      await SosService(Supabase.instance.client)
          .raiseSos(rideId: _ride.id, lon: pos.longitude, lat: pos.latitude);
      if (mounted) setState(() => _notice = 'SOS sent. Call 112 if in immediate danger.');
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _submitRating() async {
    setState(() { _error = null; _notice = null; });
    try {
      await RatingService(Supabase.instance.client)
          .submit(_ride.id, _stars, _tags.toList());
      if (mounted) setState(() { _rated = true; _notice = 'Thanks for rating!'; });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _cancel() async {
    try {
      final r = await _booking.cancelRide(_ride.id);
      if (mounted) setState(() => _ride = r);
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _ride.status != RideStatus.cancelledBeforeOtp &&
        _ride.status != RideStatus.noDriverFound &&
        _ride.status != RideStatus.completed;
    return Scaffold(
      appBar: AppBar(
        title: Text('Ride ${_ride.status.name}'),
        actions: [
          if (active)
            IconButton(
              icon: const Icon(Icons.sos, color: Colors.red),
              tooltip: 'SOS',
              onPressed: _sos,
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('${_ride.pickupText ?? ''} → ${_ride.dropText ?? ''}'),
        Text('Fare ₹${_ride.fareEstimateRs ?? '?'} · ${_ride.category} · ${_ride.mode}'),
        if (_otp != null && active)
          Card(
            color: Colors.amber.shade100,
            child: ListTile(
              title: Text('Share OTP with driver: $_otp',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              subtitle: const Text('Driver needs this to start the ride (1 credit deducted)'),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'New OTP',
                onPressed: (_ride.status == RideStatus.accepted ||
                        _ride.status == RideStatus.arrived)
                    ? _regenOtp
                    : null,
              ),
            ),
          ),
        if (_notice != null) Text(_notice!, style: const TextStyle(color: Colors.green)),
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        TextButton(
          onPressed: () => launchUrl(Uri.parse('tel:112')),
          child: const Text('Emergency call 112'),
        ),
        if (_ride.mode == 'bidding' && _ride.status == RideStatus.requested) ...[
          const SizedBox(height: 8),
          const Text('Driver offers:', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final o in _offers)
            if (o.status == 'pending')
              ListTile(
                title: Text('₹${o.amountRs} (round ${o.round})'),
                trailing: ElevatedButton(
                  onPressed: () => _acceptOffer(o),
                  child: const Text('Accept'),
                ),
              ),
          if (_offers.isEmpty) const Text('Waiting for driver offers...'),
        ],
        if (_ride.status == RideStatus.noDriverFound)
          const Text('No drivers found. Try again with a higher bid or different category.'),
        if (_ride.status == RideStatus.completed && !_rated) ...[
          const SizedBox(height: 8),
          const Text('Rate your driver:', style: TextStyle(fontWeight: FontWeight.bold)),
          Row(
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  icon: Icon(i <= _stars ? Icons.star : Icons.star_border),
                  onPressed: () => setState(() => _stars = i),
                ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final t in _ratingTags)
                FilterChip(
                  label: Text(t),
                  selected: _tags.contains(t),
                  onSelected: (s) => setState(() {
                    if (s) {
                      _tags.add(t);
                    } else {
                      _tags.remove(t);
                    }
                  }),
                ),
            ],
          ),
          ElevatedButton(onPressed: _submitRating, child: const Text('Submit rating')),
        ],
        if (active &&
            (_ride.status == RideStatus.requested ||
             _ride.status == RideStatus.accepted ||
             _ride.status == RideStatus.arrived))
          ElevatedButton(onPressed: _cancel, child: const Text('Cancel ride')),
      ]),
    );
  }
}
