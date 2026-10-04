import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dt_core/dt_core.dart';
import 'driver_background.dart';

const _steps = ['Accepted', 'Arrived', 'Started', 'Completed'];

/// Assigned-ride flow as a timeline: Arrived (300m geofence) → OTP start
/// (deducts 1 credit) → End (GPS proof) → rate + dispute.
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
      if (!mounted) return;
      final was = _ride?.status;
      setState(() => _ride = r);
      if (r.status == RideStatus.completed) _checkRated();
      if (was != null && was != r.status && r.status == RideStatus.started) {
        DtSounds.alert(title: 'Ride started', body: '1 credit deducted — drive safe');
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

  Future<void> _checkRated() async {
    try {
      final done = await RatingService(Supabase.instance.client).alreadyRated(widget.rideId);
      if (mounted) setState(() => _rated = done);
    } catch (_) {}
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
      _booking.notifyRide(widget.rideId, 'arrived');
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
      BookingService(Supabase.instance.client).notifyRide(widget.rideId, 'started');
      await _refresh();
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _end() async {
    setState(() { _busy = true; _error = null; });
    try {
      final pos = await _pos();
      final r = await RideApi(Supabase.instance.client)
          .complete(widget.rideId, pos.lon, pos.lat);
      BookingService(Supabase.instance.client).notifyRide(widget.rideId, 'completed');
      setState(() => _ride = r);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
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
              labelText: 'What happened? (breakdown, emergency…)'),
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

  int _stepIndex(RideStatus s) => switch (s) {
    RideStatus.accepted => 0,
    RideStatus.arrived => 1,
    RideStatus.started => 2,
    RideStatus.completed => 3,
    _ => 0,
  };

  @override
  Widget build(BuildContext context) {
    final live = _ride != null &&
        _ride!.status != RideStatus.completed &&
        _ride!.status != RideStatus.cancelledBeforeOtp;
    return Scaffold(
      appBar: AppBar(
        title: Text('Ride ${_ride?.status.name ?? '…'}'),
        actions: [
          if (live)
            IconButton(icon: const Icon(Icons.sos, color: Colors.redAccent),
              tooltip: Str.sos, onPressed: _sos),
        ],
      ),
      body: _ride == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_ride!.pickupText ?? ''} → ${_ride!.dropText ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                          color: Colors.green.shade50, borderRadius: BorderRadius.circular(12)),
                      child: Text('Collect ₹${_ride!.fareEstimateRs ?? '?'} in cash / your UPI',
                          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.green.shade800)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      for (var i = 0; i < _steps.length; i++)
                        Expanded(
                          child: Column(children: [
                            CircleAvatar(
                              radius: 15,
                              backgroundColor: i <= _stepIndex(_ride!.status)
                                  ? AppColors.success : Colors.grey.shade300,
                              child: Icon(
                                i < _stepIndex(_ride!.status) ? Icons.check : Icons.circle,
                                size: 14,
                                color: i <= _stepIndex(_ride!.status) ? Colors.white : Colors.grey.shade500),
                            ),
                            const SizedBox(height: 4),
                            Text(_steps[i],
                                style: TextStyle(fontSize: 10,
                                    fontWeight: i == _stepIndex(_ride!.status)
                                        ? FontWeight.w800 : FontWeight.w400)),
                          ]),
                        ),
                    ],
                  ),
                ),
              ),
              if (_notice != null) ...[
                const SizedBox(height: 8),
                DtBanner(kind: BannerKind.success, title: _notice!),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                DtBanner(kind: BannerKind.error, title: _error!),
              ],
              const SizedBox(height: 12),
              if (_ride!.status == RideStatus.accepted)
                DtPrimaryButton(label: Str.arrived, busy: _busy, onPressed: _arrived),
              if (_ride!.status == RideStatus.arrived) ...[
                const DtSectionLabel('Rider OTP — starting deducts 1 credit'),
                DtOtpBoxes(
                  value: _otp.text,
                  length: 4,
                  onChange: (v) => _otp.text = v,
                ),
                const SizedBox(height: 12),
                DtPrimaryButton(label: Str.startRide, busy: _busy, onPressed: _start),
              ],
              if (_ride!.status == RideStatus.started)
                DtPrimaryButton(label: Str.endRide, busy: _busy, onPressed: _end),
              if (_ride!.status == RideStatus.completed) ...[
                if (!_rated) ...[
                  const DtSectionLabel('Rate your rider'),
                  Center(child: DtStars(value: _stars, onChanged: (v) => setState(() => _stars = v))),
                  const SizedBox(height: 8),
                  DtPrimaryButton(label: 'Submit rating', onPressed: _submitRating),
                ],
                TextButton(onPressed: _dispute, child: const Text('Raise dispute (refund review)')),
              ],
              TextButton.icon(
                onPressed: () => launchUrl(Uri.parse('tel:112')),
                icon: const Icon(Icons.call_outlined),
                label: const Text(Str.emergencyCall),
              ),
            ]),
    );
  }
}
