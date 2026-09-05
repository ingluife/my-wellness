import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Whether Android notifications are, or become, enabled for the app.
///
/// Shared between the workout-day reminder and the workout quick-action notification so the two
/// permission prompts behave identically rather than drifting apart. [interactive] gates the OS
/// dialog to an explicit toggle in Settings — a background resync, or a state write that
/// happens to turn a setting on some other way, must never pop one.
Future<bool> ensureNotificationPermission(FlutterLocalNotificationsPlugin plugin,
    {required bool interactive}) async {
  final android =
      plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  if (android != null) {
    final enabled = await android.areNotificationsEnabled() ?? false;
    if (enabled) return true;
    if (!interactive) return false;
    return await android.requestNotificationsPermission() ?? false;
  }
  final ios = plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
  if (ios != null && interactive) {
    return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }
  return !interactive;
}
