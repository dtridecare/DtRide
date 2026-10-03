import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'booking_service.dart';
import 'config.dart';

/// Foreground GPS streaming (app open). Posts to ride_locations via
/// post_location RPC every [DtConfig.locationIntervalSec]s.
/// S3 upgrades this to flutter_background_service for screen-off tracking;
/// the server contract stays identical.
class LocationService {
  final SupabaseClient db;
  final BookingService booking;
  StreamSubscription<Position>? _sub;

  LocationService(this.db) : booking = BookingService(db);

  Future<bool> ensurePermission() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return false;
    }
    return Geolocator.isLocationServiceEnabled();
  }

  /// Notification permission, independent of Firebase config.
  /// Returns true if granted or skipped as limited; false if denied.
  Future<bool> ensureNotificationPermission() async {
    final s = await ph.Permission.notification.request();
    return s.isGranted || s.isLimited;
  }

  Future<bool> openSettings() => ph.openAppSettings();

  Future<Position> current() => Geolocator.getCurrentPosition();

  /// Starts posting pings for [rideId]. Returns false if permission denied.
  Future<bool> startRideTracking(String rideId) async {
    if (!await ensurePermission()) return false;
    await stopRideTracking();
    _sub = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
        timeLimit: Duration(seconds: DtConfig.locationIntervalSec),
      ),
    ).listen((pos) {
      booking.postLocation(rideId, pos.longitude, pos.latitude, pos.speed * 3.6)
          .catchError((_) => null);
    });
    return true;
  }

  Future<void> stopRideTracking() async {
    await _sub?.cancel();
    _sub = null;
  }
}
