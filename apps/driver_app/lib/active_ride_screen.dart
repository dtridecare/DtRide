import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dt_core/dt_core.dart';
import 'driver_background.dart';

/// Pack active ride: mini map, arrived + waiting timer, OTP boxes,
/// Call/Message/Navigate, agreed-fare bar.
class ActiveRideScreen extends StatefulWidget {
  final String rideId;
  const ActiveRideScreen({super.key, required this.rideId});

  @override
  State<ActiveRideScreen> createState() => _ActiveRideScreenState();
}

class _ActiveRideScreenState extends State<ActiveRideScreen> {
  Ride? _ride;
  Map<String, dynamic>? _party;
  String _otp = '';
  final _disputeBody = TextEditingController();
  String? _error;
  String? _notice;
  bool _busy = false;
  late final LocationService _loc;
  RealtimeChannel? _ch;
  int _stars = 5;
  bool _rated = false;
  Timer? _timer;
  int _waitS = 0;

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
      if (r.driverId != null && _party == null) _loadParty();
      if (was != null && was != r.status && r.status == RideStatus.started) {
        DtSounds.alert(title: 'Ride started', body: '1 credit deducted — drive safe');
      }
    });
    _loc.startRideTracking(widget.rideId);
    startTrackingService();
    PushService(Supabase.instance.client).subscribeRide(widget.rideId);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _waitS++);
    });
  }

  Future<void> _refresh() async {
    try {
      final r = await _booking.getRide(widget.rideId);
      if (!mounted) return;
      setState(() => _ride = r);
      if (r.driverId != null) _loadParty();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _loadParty() async {
    try {
      final p = await KycService(Supabase.instance.client)
          .db
          .rpc('ride_party_public', params: {'p_ride': widget.rideId});
      if (mounted) setState(() => _party = Map<String, dynamic>.from(p as Map));
    } catch (_) {}
  }

  Future<void> _checkRated() async {
    try {
      final done = await RatingService(Supabase.instance.client).alreadyRated(widget.rideId);
      if (mounted) setState(() => _rated = done);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
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
      setState(() { _ride = r; _waitS = 0; });
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_otp.length < 4) {
      setState(() => _error = 'Enter the 4-digit code from the rider.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await RideApi(Supabase.instance.client)
          .startWithOtp(widget.rideId, _otp);
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

  String get _riderName => ((_party?['name'] ?? 'Rider') as String);

  @override
  Widget build(BuildContext context) {
    final live = _ride != null &&
        _ride!.status != RideStatus.completed &&
        _ride!.status != RideStatus.cancelledBeforeOtp;
    return Scaffold(
      body: _ride == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              SizedBox(
                height: 170,
                child: Stack(children: [
                  FlutterMap(
                    options: MapOptions(
                      initialCenter: const LatLng(28.6139, 77.2090),
                      initialZoom: 14,
                      interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.dtride.driver_app',
                      ),
                    ],
                  ),
                  if (live)
                    Positioned(
                      right: 14, top: 40,
                      child: GestureDetector(
                        onTap: _sos,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(999)),
                          child: const Text('SOS',
                              style: TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 11, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                ]),
              ),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
                  child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                      children: [
                        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                          Text(
                            _ride!.status == RideStatus.arrived
                                ? 'Arrived at pickup'
                                : _ride!.status == RideStatus.started
                                    ? 'Trip in progress'
                                    : _ride!.status == RideStatus.completed
                                        ? 'Trip completed'
                                        : 'Heading to pickup',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
                          if (_ride!.status == RideStatus.arrived)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: const Color(0xFFDCFCE7),
                                  borderRadius: BorderRadius.circular(999)),
                              child: Text(
                                'Waiting ${_waitS ~/ 60}:${(_waitS % 60).toString().padLeft(2, '0')}',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xFF166534))),
                            ),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          CircleAvatar(
                            backgroundColor: AppColors.accent,
                            child: Text(
                              _riderName.trim().isEmpty
                                  ? 'R'
                                  : _riderName.trim().split(RegExp(r'\s+'))
                                      .map((w) => w[0]).take(2).join().toUpperCase(),
                              style: const TextStyle(
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w500, fontSize: 12)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_riderName,
                                      style: const TextStyle(fontWeight: FontWeight.w500)),
                                  Text(
                                    '${_party?['rating'] ?? '—'} rating · ${_party?['trips'] ?? 0} trips',
                                    style: const TextStyle(
                                        fontSize: 12, color: AppColors.muted)),
                                ]),
                          ),
                        ]),
                        if (_notice != null) ...[
                          const SizedBox(height: 8),
                          DtBanner(kind: BannerKind.success, title: _notice!),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          DtBanner(kind: BannerKind.error, title: _error!),
                        ],
                        if (_ride!.status == RideStatus.accepted) ...[
                          const SizedBox(height: 12),
                          DtPrimaryButton(
                              label: "I've arrived", busy: _busy, onPressed: _arrived),
                        ],
                        if (_ride!.status == RideStatus.arrived) ...[
                          const SizedBox(height: 12),
                          const Text("Enter rider's 4-digit code",
                              style: TextStyle(fontWeight: FontWeight.w500)),
                          const SizedBox(height: 8),
                          DtOtpBoxes(
                              value: _otp, length: 4,
                              onChange: (v) => setState(() => _otp = v)),
                          const SizedBox(height: 4),
                          const Text('The trip can only start with the correct code.',
                              style: TextStyle(fontSize: 12, color: AppColors.muted)),
                          const SizedBox(height: 12),
                          DtPrimaryButton(
                              label: 'Verify and start trip',
                              busy: _busy, onPressed: _start),
                        ],
                        if (_ride!.status == RideStatus.started) ...[
                          const SizedBox(height: 12),
                          DtPrimaryButton(
                              label: 'End trip', busy: _busy, onPressed: _end),
                        ],
                        const SizedBox(height: 12),
                        Row(children: [
                          _action(Icons.call_outlined, 'Call',
                              () => launchUrl(Uri.parse('tel:'))),
                          _action(Icons.message_outlined, 'Message',
                              () => launchUrl(Uri.parse('sms:'))),
                          _action(Icons.navigation_outlined, 'Navigate', () {
                            final t = _ride!.dropText ?? '';
                            launchUrl(Uri.parse(
                                'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(t)}'));
                          }),
                        ]),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12)),
                          child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Agreed fare',
                                    style: TextStyle(
                                        fontSize: 12, color: AppColors.muted)),
                                Text('₹${_ride!.fareEstimateRs ?? '?'} · collect from rider',
                                    style: const TextStyle(fontWeight: FontWeight.w500)),
                              ]),
                        ),
                        if (_ride!.status == RideStatus.completed) ...[
                          const SizedBox(height: 12),
                          if (!_rated) ...[
                            const Text('Rate your rider',
                                style: TextStyle(fontWeight: FontWeight.w500)),
                            Center(
                                child: DtStars(
                                    value: _stars,
                                    onChanged: (v) => setState(() => _stars = v))),
                            const SizedBox(height: 8),
                            DtPrimaryButton(
                                label: 'Submit rating', onPressed: _submitRating),
                          ],
                          TextButton(
                              onPressed: _dispute,
                              child: const Text('Raise dispute (refund review)')),
                        ],
                      ]),
                ),
              ),
            ]),
    );
  }

  Widget _action(IconData icon, String label, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          height: 40, width: 40,
          decoration: const BoxDecoration(
              color: AppColors.surface, shape: BoxShape.circle),
          child: Icon(icon, size: 18),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ]),
    ),
  );
}
