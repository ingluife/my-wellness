import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models/app_state.dart';
import '../domain/i18n.dart';
import 'notification_permission.dart';

/// The workout-day reminder.
///
/// One repeating local notification per weekday that has a routine in the weekly plan — no
/// server involved, unlike the self-hosted flavour's Web Push. Cheap enough to re-run after
/// any state change, because the plan or the reminder time may just have been edited.
class Reminders {
  Reminders._();

  static final Reminders instance = Reminders._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// The underlying plugin, for anything else that needs to share its notification permission —
  /// see [ensureNotificationPermission] and the workout quick-action notification's Settings
  /// toggle.
  FlutterLocalNotificationsPlugin get plugin => _plugin;

  /// Ids 100..106 — one per weekday, in `getDay()` numbering, so a resync can cancel exactly
  /// what it is about to replace without touching anything else.
  static const _baseId = 100;

  static const _channel = AndroidNotificationDetails(
    'workout_reminder',
    'Workout day reminder',
    channelDescription: 'Reminds you on days that have a routine planned.',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation(localTimeZone()));
    } catch (_) {
      // An unknown zone name is not worth failing over; UTC still fires, just not to the
      // minute for a traveller.
    }
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    ));
    _ready = true;
  }

  /// The IANA zone name, which is what `timezone` indexes by.
  static String localTimeZone() => DateTime.now().timeZoneName;

  /// (Re)schedule everything.
  ///
  /// [interactive] gates the OS permission prompt to the Settings toggle; a background resync
  /// after an ordinary edit never pops a dialog. Returns false when permission was refused,
  /// so the toggle can stay off rather than lying about being on.
  Future<bool> sync(AppState s, {bool interactive = false}) async {
    try {
      await init();
      for (var d = 0; d < 7; d++) {
        await _plugin.cancel(_baseId + d);
      }
      if (!s.reminder.on) return true;
      if (!await _ensurePermission(interactive)) return false;

      final parts = (s.reminder.time).split(':');
      final hour = int.tryParse(parts.first) ?? 8;
      final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

      for (final entry in s.week.entries) {
        final day = int.tryParse(entry.key);
        final routine = s.routines.where((r) => r.id == entry.value).firstOrNull;
        if (day == null || routine == null) continue;
        await _plugin.zonedSchedule(
          _baseId + day,
          t('Workout day'),
          t('{0} is on the plan today — let’s go!', routine.name),
          _nextInstance(day, hour, minute),
          const NotificationDetails(android: _channel, iOS: DarwinNotificationDetails()),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensurePermission(bool interactive) =>
      ensureNotificationPermission(_plugin, interactive: interactive);

  /// The next occurrence of a weekday at a time of day.
  ///
  /// `getDay()` counts Sunday as 0; Dart's `weekday` counts Monday as 1, and the schedule has
  /// to land on the day the weekly plan means.
  tz.TZDateTime _nextInstance(int jsWeekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    // Dart weekday 7 is Sunday, which is `getDay()` 0.
    final target = jsWeekday == 0 ? 7 : jsWeekday;
    while (next.weekday != target || !next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }
}
