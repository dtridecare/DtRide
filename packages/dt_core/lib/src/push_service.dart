import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sounds.dart';

/// Background handler must be top-level. The OS renders the push itself;
/// nothing to do here except stay registered.
@pragma('vm:entry-point')
Future<void> dtBackgroundHandler(RemoteMessage message) async {}

/// FCM wiring: Firebase init (best-effort — needs google-services files) →
/// permission → token saved to push_tokens → per-ride topics.
/// Foreground messages render locally with the DT chime.
/// Server fan-out lives in send-push / notify-ride / dispatch functions.
class PushService {
  final SupabaseClient db;
  PushService(this.db);

  Future<bool> ensureFirebase() async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> init() async {
    if (!await ensureFirebase()) return false;
    try {
      FirebaseMessaging.onBackgroundMessage(dtBackgroundHandler);
      final fm = FirebaseMessaging.instance;
      final settings = await fm.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return false;
      }
      await _saveToken(fm);
      // Tokens rotate: re-save on refresh or pushes die silently.
      fm.onTokenRefresh.listen((_) => _saveToken(fm)).onError((_) {});
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null) {
          DtSounds.alert(title: n.title ?? 'DT Ride', body: n.body ?? '');
        }
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveToken(FirebaseMessaging fm) async {
    try {
      final token = await fm.getToken();
      final user = db.auth.currentUser;
      if (token == null || user == null) return;
      await db.from('push_tokens').upsert(
          {'user_id': user.id, 'token': token, 'platform': 'android'});
    } catch (_) {}
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
