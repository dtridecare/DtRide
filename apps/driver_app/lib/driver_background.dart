import 'package:flutter_background_service/flutter_background_service.dart';

/// Keeps the driver process alive (foreground notification) so the
/// main-isolate GPS stream in [LocationService] survives screen-off.
/// Location posting itself stays in the main isolate via post_location RPC.
///
/// Native setup still required once (one time):
/// `cd apps/driver_app && flutter create --org com.dtride --project-name driver_app .`
/// then add in AndroidManifest:
/// `<uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />`
/// `<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />`
/// and set `foregroundServiceType="location"` on the tracking service (plugin handles most).

Future<void> initDriverBackground() async {
  try {
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'dt_ride_tracking',
        initialNotificationTitle: 'DT Ride Driver',
        initialNotificationContent: 'Online — sharing location',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onStart,
        onBackground: _onIosBackground,
      ),
    );
  } catch (_) {}
}

@pragma('vm:entry-point')
void _onStart(ServiceInstance service) {
  service.on('stop').listen((_) => service.stopSelf());
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async => true;

/// Call when the driver goes online / accepts a ride.
Future<void> startTrackingService() async {
  try {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) await service.startService();
  } catch (_) {}
}

/// Call when the driver goes offline.
Future<void> stopTrackingService() async {
  try {
    FlutterBackgroundService().invoke('stop');
  } catch (_) {}
}
