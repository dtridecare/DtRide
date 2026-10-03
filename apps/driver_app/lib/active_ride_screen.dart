import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dt_core/dt_core.dart';
import 'driver_background.dart';

/// Assigned-ride flow: Arrived (300m geofence) -> OTP start (deducts 1 credit)
/// -> End (GPS proof, flags suspicious). Foreground GPS pings while active.
class ActiveRideScreen extends StatefulWidget {
  final String rideId;
  const ActiveRideScreen({super.key, required this.rideId});

  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen> {
  Ride? _ride;
  final _otp = TextEditingController();
  final _disputeBody = TextEditingController();
  String? _error;
  String? _notice;
  bool _busy = false;
  late final LocationService _loc;
  RealtimeChannel? _ch;
  int _stars = 5;
  bool _rated = false;

  BookingService get _booking => BookingService(Supabase.instance.client);

  @override
  void initState() {
    super.initState();
    _loc = LocationService(Supabase.instance.client);
    _refresh();
    _ch = _booking.watchRide(widget.rideId, (r) {
      if (mounted) {
        setState(() => _ride = r);
        if (r.status == RideStatus.completed) _checkRated();
      }
    });
    _loc.startRideTracking(widget.rideId);
    startTrackingService();
    PushService(Supabase.instance.client).subscribeRide(widget.rideId);
  }

  Future<void> _refresh() async {
    try {
      final r = await _booking.getRide(widget.rideId);
      if (mounted) setState(() => _ride = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  void dispose() {
    if (_ch != null) Supabase.instance.client.removeChannel(_ch!);
    _loc.stopRideTracking();
    super.dispose();
  }

  Future<({double lon, double lat})> _pos() async {
    final p = await Geolocator.getCurrentPosition();
    return (lon: p.longitude, lat: p.latitude);
  }

  Future<void> _arrived() async {
    setState(() { _busy = true; _error = null; });
    try {
      final pos = await _pos();
      final r = await _booking.markArrived(widget.rideId, pos.lon, pos.lat);
      setState(() => _ride = r);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    setState(() { _busy = true; _error = null; });
    try {
      await RideApi(Supabase.instance.client)
          .startWithOtp(widget.rideId, _otp.text.trim());
      await _refresh();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _checkRated() async {
    try {
      final done = await RatingService(Supabase.instance.client).alreadyRated(widget.rideId);
      if (mounted) setState(() => _rated = done);
    } catch (_) {}
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
      final pos = await _pos();
      await SosService(Supabase.instance.client)
          .raiseSos(rideId: widget.rideId, lon: pos.lon, lat: pos.lat);
      if (mounted) setState(() => _notice = 'SOS sent. Call 112 if in immediate danger.');
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _submitRating() async {
    setState(() { _error = null; _notice = null; });
    try {
      await RatingService(Supabase.instance.client).submit(widget.rideId, _stars);
      if (mounted) setState(() { _rated = true; _notice = 'Rating submitted.'; });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _dispute() async {
    final subject = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Raise dispute (credit refund review)'),
        content: TextField(
          controller: _disputeBody,
          decoration: const InputDecoration(
              labelText: 'What happened? (breakdown, emergency...)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, 'credit_review'), child: const Text('Submit')),
        ],
      ),
    );
    if (subject == null) return;
    try {
      await SosService(Supabase.instance.client).raiseDispute(
        rideId: widget.rideId, subject: subject, body: _disputeBody.text.trim());
      if (mounted) setState(() => _notice = 'Dispute raised. Admin reviews within 24h.');
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _end() async {
    setState(() { _busy = true; _error = null; });
    try {
      final pos = await _pos();
      final r = await RideApi(Supabase.instance.client)
          .complete(widget.rideId, pos.lon, pos.lat);
      setState(() => _ride = r);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text('Ride ${_ride?.status.name ?? '...'}'),
      actions: [
        if (_ride != null &&
            _ride!.status != RideStatus.completed &&
            _ride!.status != RideStatus.cancelledBeforeOtp)
          IconButton(
            icon: const Icon(Icons.sos, color: Colors.red),
            tooltip: 'SOS',
            onPressed: _sos,
          ),
      ],
    ),
    body: _ride == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(padding: const EdgeInsets.all(20), children: [
            Text('${_ride!.pickupText ?? ''} → ${_ride!.dropText ?? ''}'),
            Text('Fare ₹${_ride!.fareEstimateRs ?? '?'} (collect cash/UPI on your QR)'),
            if (_notice != null) Text(_notice!, style: const TextStyle(color: Colors.green)),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
            TextButton(
              onPressed: () => launchUrl(Uri.parse('tel:112')),
              child: const Text('Emergency call 112'),
            ),
            const SizedBox(height: 12),
            if (_ride!.status == RideStatus.accepted)
              ElevatedButton(
                onPressed: _busy ? null : _arrived,
                child: const Text("I've arrived"),
              ),
            if (_ride!.status == RideStatus.arrived) ...[
              TextField(controller: _otp, keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Rider OTP (starts ride, -1 credit)')),
              ElevatedButton(
                onPressed: _busy ? null : _start,
                child: const Text('Start ride'),
              ),
            ],
            if (_ride!.status == RideStatus.started)
              ElevatedButton(
                onPressed: _busy ? null : _end,
                child: const Text('End ride'),
              ),
            if (_ride!.status == RideStatus.completed) ...[
              if (!_rated) ...[
                const Text('Rate your rider:', style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    for (var i = 1; i <= 5; i++)
                      IconButton(
                        icon: Icon(i <= _stars ? Icons.star : Icons.star_border),
                        onPressed: () => setState(() => _stars = i),
                      ),
                  ],
                ),
                ElevatedButton(onPressed: _submitRating, child: const Text('Submit rating')),
              ],
              TextButton(onPressed: _dispute, child: const Text('Raise dispute (refund review)')),
            ],
          ]),
  );
}
