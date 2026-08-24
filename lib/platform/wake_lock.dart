import 'package:wakelock_plus/wakelock_plus.dart';

/// Keeps the display on while a workout is running, so nobody has to unlock their phone
/// between sets.
///
/// Bound to the *workout*, not to the route: checking Stats mid-session keeps the screen on,
/// because you are still training.
class ScreenWakeLock {
  ScreenWakeLock._();

  static final ScreenWakeLock instance = ScreenWakeLock._();

  bool _wanted = false;

  Future<void> set(bool on) async {
    if (on == _wanted) return;
    _wanted = on;
    try {
      await WakelockPlus.toggle(enable: on);
    } catch (_) {
      // iOS refuses in Low Power Mode, and some devices refuse on low battery. Nothing the
      // user could act on — stay quiet.
    }
  }
}
