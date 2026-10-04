import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// DT Ride chime: local alerts play res/raw/dt_chime (Android) instead of
/// the phone's default notification sound, so riders/drivers instantly know
/// it's us. FCM pushes should set sound 'dt_chime' + channel
/// 'dt_ride_alerts' (see reminders function) to reuse the same channel.
class DtSounds {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    try {
      await _plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ));
      const channel = AndroidNotificationChannel(
        'dt_ride_alerts', 'DT Ride alerts',
        description: 'Ride updates with the DT Ride chime',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('dt_chime'),
        playSound: true,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      _ready = true;
    } catch (_) {}
  }

  static Future<void> alert({required String title, required String body}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'dt_ride_alerts', 'DT Ride alerts',
            importance: Importance.high,
            priority: Priority.high,
            sound: RawResourceAndroidNotificationSound('dt_chime'),
            playSound: true,
          ),
        ),
      );
    } catch (_) {}
  }
}
