import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// FCM wiring: permission -> token saved to push_tokens -> topic per ride.
/// Best-effort: if Firebase isn't configured (no google-services files yet),
/// init() returns false and the app works without push (realtime covers S3).
/// Server fan-out (dispatch -> FCM send) lands with production keys.
class PushService {
  final SupabaseClient db;
  PushService(this.db);

  Future<bool> init() async {
    try {
      final fm = FirebaseMessaging.instance;
      final settings = await fm.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return false;
      }
      final token = await fm.getToken();
      if (token == null) return false;
      final user = db.auth.currentUser;
      if (user == null) return false;
      await db.from('push_tokens').upsert(
          {'user_id': user.id, 'token': token, 'platform': 'android'});
      FirebaseMessaging.onMessage.listen((_) {});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> subscribeRide(String rideId) async {
    try {
      await FirebaseMessaging.instance.subscribeToTopic('ride_$rideId');
    } catch (_) {}
  }

  Future<void> unsubscribeRide(String rideId) async {
    try {
      await FirebaseMessaging.instance.unsubscribeFromTopic('ride_$rideId');
    } catch (_) {}
  }
}
