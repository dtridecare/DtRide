import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:dt_core/dt_core.dart';

const _ratingTags = ['Polite', 'Clean car', 'Safe driving', 'On time', 'Rash driving', 'Overcharged'];

/// Pack trip screen: mini map + SOS, driver card, OTP, fare chip, actions.
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
  Map<String, dynamic>? _party;
  LatLng? _from, _to;
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
    var prev = _ride.status;
    _rideCh = svc.watchRide(_ride.id, (r) {
      if (!mounted) return;
      final was = prev;
      prev = r.status;
      setState(() => _ride = r);
      if (r.status == RideStatus.completed) _checkRated();
      if (r.driverId != null && _party == null) _loadParty();
      if (was != r.status &&
          (r.status == RideStatus.accepted ||
           r.status == RideStatus.arrived ||
           r.status == RideStatus.started)) {
        DtSounds.alert(
          title: 'DT Ride update',
          body: r.status == RideStatus.accepted
              ? 'Driver accepted — heading to pickup'
              : r.status == RideStatus.arrived
                  ? 'Driver arrived — share your OTP'
                  : 'Ride started — enjoy your trip');
      }
    });
    if (_ride.mode == 'bidding') {
      _offerCh = svc.watchOffers(_ride.id, _loadOffers);
      _loadOffers();
    }
    if (_ride.status == RideStatus.completed) _checkRated();
    if (_ride.driverId != null) _loadParty();
    PushService(Supabase.instance.client).subscribeRide(_ride.id);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final base = _ride.createdAt ?? DateTime.now();
      setState(() => _elapsedS = DateTime.now().difference(base).inSeconds);
    });
    _geocodeEndpoints();
  }

  Future<void> _geocodeEndpoints() async {
    try {
      final maps = OsmAdapter();
      final a = _ride.pickupText == null ? null : await maps.geocode(_ride.pickupText!);
      final b = _ride.dropText == null ? null : await maps.geocode(_ride.dropText!);
      if (mounted) {
        setState(() {
          if (a != null) _from = LatLng(a.lat, a.lon);
          if (b != null) _to = LatLng(b.lat, b.lon);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadParty() async {
    try {
      final p = await KycService(Supabase.instance.client)
          .db
          .rpc('ride_party_public', params: {'p_ride': _ride.id});
      if (mounted) setState(() => _party = Map<String, dynamic>.from(p as Map));
    } catch (_) {}
  }

  Future<void> _loadOffers() async {
    try {
      final before = _offers.where((o) => o.status == 'pending').length;
      final offers = await _booking.offers(_ride.id);
      final after = offers.where((o) => o.status == 'pending').length;
      if (mounted) setState(() => _offers = offers);
      if (after > before) {
        DtSounds.alert(title: 'New driver offer', body: 'A driver countered — open to review');
      }
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
      _booking.notifyRide(_ride.id, 'offer_accepted');
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
      _booking.notifyRide(_ride.id, 'cancelled');
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
      final ok = await LocationService(Supabase.instance.client).ensurePermission();
      if (!ok) throw StateError('location off');
      final pos = await Geolocator.getCurrentPosition();
      await SosService(Supabase.instance.client)
          .raiseSos(rideId: _ride.id, lon: pos.longitude, lat: pos.latitude);
      if (mounted) setState(() => _notice = 'SOS sent. Call 112 if in immediate danger.');
    } catch (e) {
      final msg = '$e';
      setState(() => _error = msg.contains('location off')
          ? 'SOS needs location — enable it in Settings, then retry. Meanwhile call 112.'
          : msg);
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

  void _shareTrip() {
    Share.share(
      'My DtRide trip: ${_ride.pickupText ?? ''} to ${_ride.dropText ?? ''}. '
      'Fare ₹${_ride.fareEstimateRs ?? '?'}. Track me — ride ${_ride.id.substring(0, 8)}.');
  }

  String get _initials {
    final name = (_party?['name'] ?? 'D') as String;
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.characters.take(2).toString().toUpperCase();
    return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final active = _ride.status != RideStatus.cancelledBeforeOtp &&
        _ride.status != RideStatus.noDriverFound &&
        _ride.status != RideStatus.completed;
    final title = switch (_ride.status) {
      RideStatus.requested => 'Finding your driver',
      RideStatus.accepted => '${(_party?['name'] ?? 'Driver')} is arriving',
      RideStatus.arrived => 'Driver arrived',
      RideStatus.started => 'Trip in progress',
      RideStatus.completed => 'Trip completed',
      _ => 'Ride ${_ride.status.name}',
    };
    return Scaffold(
      body: Column(children: [
        SizedBox(
          height: 220,
          child: Stack(children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: _from ?? const LatLng(28.6139, 77.2090),
                initialZoom: 13,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.dtride.rider_app',
                ),
                MarkerLayer(markers: [
                  if (_from != null)
                    Marker(point: _from!, width: 40, height: 40,
                      child: const Icon(Icons.location_pin, color: Colors.green, size: 36)),
                  if (_to != null)
                    Marker(point: _to!, width: 40, height: 40,
                      child: const Icon(Icons.location_pin, color: Colors.red, size: 36)),
                ]),
              ],
            ),
            if (active)
              Positioned(
                right: 14, top: 40,
                child: GestureDetector(
                  onTap: _sos,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(999)),
                    child: const Text('SOS',
                        style: TextStyle(color: AppColors.danger, fontSize: 11, fontWeight: FontWeight.w700)),
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
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 20), children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Expanded(child: Text(title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500))),
                if (_ride.status == RideStatus.requested)
                  Text('0:${(_elapsedS % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(color: AppColors.muted)),
              ]),
              if (_party != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  CircleAvatar(
                    backgroundColor: AppColors.accent,
                    child: Text(_initials,
                        style: const TextStyle(
                            color: AppColors.ink, fontWeight: FontWeight.w500, fontSize: 12)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((_party!['name'] ?? 'Driver') as String,
                          style: const TextStyle(fontWeight: FontWeight.w500)),
                      Text(
                        '${_party!['rating'] ?? '—'} rating · ${_party!['trips'] ?? 0} trips'
                        '${_party!['car'] != null ? ' · ${_party!['car']}' : ''}',
                        style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                    ]),
                  ),
                  if (_party!['plate'] != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
                      child: Text((_party!['plate']) as String,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    ),
                ]),
              ],
              if (_otp != null && active) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Share this code with your driver to start',
                        style: TextStyle(fontSize: 12, color: AppColors.muted)),
                    const SizedBox(height: 8),
                    Row(children: [
                      for (final ch in _otp!.split(''))
                        Container(
                          margin: const EdgeInsets.only(right: 8),
                          height: 48, width: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                              color: Colors.white, borderRadius: BorderRadius.circular(10)),
                          child: Text(ch,
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500)),
                        ),
                      const Spacer(),
                      TextButton(onPressed: _regenOtp, child: const Text('New code')),
                    ]),
                  ]),
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
                const SizedBox(height: 8),
                Text('${_offers.where((o) => o.status == 'pending').length} drivers responded',
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                for (final o in _offers)
                  if (o.status == 'pending')
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(14)),
                      child: Row(children: [
                        const CircleAvatar(child: Icon(Icons.person_outline, size: 18)),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('Driver offer')),
                        Text('₹${o.amountRs}',
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => _acceptOffer(o),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                                color: AppColors.ink, borderRadius: BorderRadius.circular(10)),
                            child: const Text('Accept',
                                style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                      ]),
                    ),
              ],
              if (_ride.status == RideStatus.noDriverFound)
                const DtBanner(kind: BannerKind.warn,
                    title: 'No drivers found', subtitle: 'Try a higher bid or another category.'),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Agreed fare',
                      style: TextStyle(fontSize: 12, color: AppColors.muted)),
                  Text('₹${_ride.fareEstimateRs ?? '?'}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500)),
                ]),
                const Row(children: [
                  Icon(Icons.payments_outlined, size: 14),
                  SizedBox(width: 4),
                  Text('Pay driver directly', style: TextStyle(fontSize: 12)),
                ]),
              ]),
              if (_ride.status == RideStatus.completed && !_rated) ...[
                const SizedBox(height: 12),
                const Text('Rate your driver',
                    style: TextStyle(fontWeight: FontWeight.w500)),
                Center(child: DtStars(value: _stars, onChanged: (v) => setState(() => _stars = v))),
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
              ],
              const SizedBox(height: 12),
              Row(children: [
                _action(Icons.call_outlined, 'Call',
                    () => launchUrl(Uri.parse('tel:112'))),
                _action(Icons.message_outlined, 'Message',
                    () => launchUrl(Uri.parse('sms:'))),
                _action(Icons.share_outlined, 'Share trip', _shareTrip),
                _action(Icons.close, active ? 'Cancel' : 'Done', active
                    ? _cancel
                    : () => Navigator.of(context).pop()),
              ]),
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
