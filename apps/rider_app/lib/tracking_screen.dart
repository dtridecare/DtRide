import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:dt_core/dt_core.dart';

const _ratingTags = ['Polite', 'Clean car', 'Safe driving', 'On time', 'Rash driving', 'Overcharged'];

/// Live ride status: status banner, OTP card, offers, SOS, rating.
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
  Timer? _timer;
  int _elapsedS = 0;

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
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final base = _ride.createdAt ?? DateTime.now();
      setState(() => _elapsedS = DateTime.now().difference(base).inSeconds);
    });
  }

  Future<void> _loadOffers() async {
    try {
      final offers = await _booking.offers(_ride.id);
      if (mounted) setState(() => _offers = offers);
    } catch (_) {}
  }

  Future<void> _checkRated() async {
    try {
      final done = await RatingService(Supabase.instance.client).alreadyRated(_ride.id);
      if (mounted) setState(() => _rated = done);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
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

  Future<void> _regenOtp() async {
    setState(() { _error = null; _notice = null; });
    try {
      final otp = await _booking.regenerateOtp(_ride.id);
      if (mounted) setState(() { _otp = otp; _notice = 'New OTP generated'; });
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

  Color _statusColor(RideStatus s) => switch (s) {    RideStatus.requested => Colors.amber.shade700,
    RideStatus.accepted || RideStatus.arrived => Colors.blue.shade700,
    RideStatus.started => AppColors.success,
    RideStatus.completed => AppColors.ink,
    _ => AppColors.danger,
  };

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
            IconButton(icon: const Icon(Icons.sos, color: Colors.redAccent),
              tooltip: Str.sos, onPressed: _sos),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [AppColors.primaryDark, _statusColor(_ride.status)]),
            borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_ride.pickupText ?? ''} → ${_ride.dropText ?? ''}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('₹${_ride.fareEstimateRs ?? '?'} · ${_ride.category} · ${_ride.mode}',
                style: const TextStyle(color: Colors.white70)),
          ]),
        ),
        if (_ride.status == RideStatus.requested) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const SizedBox(
                height: 26, width: 26,
                child: CircularProgressIndicator(strokeWidth: 3)),
              title: const Text('Finding your driver…',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                  'Waiting ${_elapsedS ~/ 60}:${(_elapsedS % 60).toString().padLeft(2, '0')} · nearest drivers notified'),
            ),
          ),
        ],
        if (_otp != null && active) ...[
          const SizedBox(height: 12),
          Card(
            color: Colors.amber.shade50,
            child: ListTile(
              leading: const Icon(Icons.key, color: Colors.amber),
              title: Text(_otp!,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 6)),
              subtitle: Text(Str.shareOtp, style: const TextStyle(fontSize: 12)),
              trailing: IconButton(icon: const Icon(Icons.refresh), onPressed:
                  (_ride.status == RideStatus.accepted || _ride.status == RideStatus.arrived)
                      ? _regenOtp : null),
            ),
          ),
        ],
        if (_notice != null) ...[
          const SizedBox(height: 8),
          DtBanner(kind: BannerKind.success, title: _notice!),
        ],
        if (_error != null) ...[
          const SizedBox(height: 8),
          DtBanner(kind: BannerKind.error, title: _error!),
        ],
        if (_ride.mode == 'bidding' && _ride.status == RideStatus.requested) ...[
          const SizedBox(height: 12),
          const DtSectionLabel('Driver offers'),
          for (final o in _offers)
            if (o.status == 'pending')
              Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.directions_car)),
                  title: Text('₹${o.amountRs}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                  subtitle: Text('Round ${o.round}'),
                  trailing: DtPrimaryButton(label: 'Accept', onPressed: () => _acceptOffer(o)),
                ),
              ),
          if (_offers.isEmpty)
            const Text('Waiting for driver offers…', style: TextStyle(color: AppColors.muted)),
        ],
        if (_ride.status == RideStatus.noDriverFound)
          const DtBanner(kind: BannerKind.warn,
              title: 'No drivers found', subtitle: 'Try a higher bid or another category.'),
        if (_ride.status == RideStatus.completed && !_rated) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Text(Str.rateDriver, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                DtStars(value: _stars, onChanged: (v) => setState(() => _stars = v)),
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
                const SizedBox(height: 8),
                DtPrimaryButton(label: 'Submit rating', onPressed: _submitRating),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => launchUrl(Uri.parse('tel:112')),
              icon: const Icon(Icons.call),
              label: const Text(Str.emergencyCall),
            ),
          ),
          const SizedBox(width: 8),
          if (active &&
              (_ride.status == RideStatus.requested ||
               _ride.status == RideStatus.accepted ||
               _ride.status == RideStatus.arrived))
            Expanded(
              child: OutlinedButton(
                onPressed: _cancel,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                child: const Text(Str.cancelRide),
              ),
            ),
        ]),
      ]),
    );
  }
}
