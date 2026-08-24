import 'dart:math' as math;

import 'package:intl/intl.dart';

import 'i18n.dart';

/// Formatting + date helpers, ported from lib/format.js.

String isoOf(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String todayISO() => isoOf(DateTime.now());

/// An ISO day parsed at noon, the way every date read in the app is.
///
/// Midday, not midnight: a date-only string parsed as local midnight lands on the previous
/// day in any timezone behind UTC once a DST shift is involved, and a workout logged on the
/// wrong day is a bug you only notice a week later.
DateTime dayOf(String iso) => DateTime.parse('${iso}T12:00:00');

/// English day and month names — these strings are the i18n keys.
const dayn = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const days = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const monthsLong = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December'];

/// JavaScript's `getDay()`: 0 is Sunday. Dart's `weekday` is 1..7 with Monday first, and the
/// weekly plan is keyed on the JS numbering, so every read goes through this.
int jsDay(DateTime d) => d.weekday % 7;

/// "24 Aug", or "Sun, 24 Aug" when [long] — the ICU skeletons matching the source's
/// `toLocaleDateString` options, so the order follows the language.
String fmtDate(String iso, [bool long = false]) {
  final d = dayOf(iso);
  return (long ? DateFormat.MMMEd(dateLocale) : DateFormat.MMMd(dateLocale)).format(d);
}

String fmtDur(int ms) {
  final m = ms ~/ 60000;
  return m >= 60 ? '${m ~/ 60}h ${m % 60}m' : '$m min';
}

/// Imported history has no clock — an unknown duration is left out rather than shown as
/// "0 min".
List<String> durPart(int ms) => ms >= 60000 ? [fmtDur(ms)] : const [];

/// One decimal place, in the UI language's own number format.
String fmtNum(num? n) {
  final v = ((n ?? 0) * 10).round() / 10;
  return NumberFormat.decimalPattern(dateLocale).format(v);
}

/// Volume stays in the profile's unit throughout: the old shorthand turned anything over
/// 10 000 into "t", which is wrong for a pound profile and made one list mix "18.8t" with
/// "7'535 kg" — two numbers you cannot compare at a glance.
String fmtVol(num? v, String unit) => '${fmtNum(v)} $unit';

/// Plural forms are not automatic when the English string is the key.
String exCount(int n) => t(n == 1 ? '{0} exercise' : '{0} exercises', n);

/// ISO-8601 week, as "year-week". The key every streak and weekly aggregate is grouped on.
String weekKey(String d) {
  final dt = dayOf(d);
  final day = (jsDay(dt) + 6) % 7;
  // Calendar arithmetic, not duration arithmetic: adding days through the constructor keeps
  // the time of day across a DST boundary, which is what `setDate` does in the source.
  final thu = DateTime(dt.year, dt.month, dt.day + 3 - day, 12);
  final jan4 = DateTime(thu.year, 1, 4);
  final week = 1 +
      (((thu.difference(jan4).inMilliseconds / 86400000) - 3 + ((jsDay(jan4) + 6) % 7)) / 7)
          .round();
  return '${thu.year}-$week';
}

/// The Monday of an ISO date, as ms — the x position a week's point sits at.
int mondayOf(String iso) {
  final d = dayOf(iso);
  return DateTime(d.year, d.month, d.day - ((jsDay(d) + 6) % 7), 12).millisecondsSinceEpoch;
}

String localTZ() {
  try {
    return DateTime.now().timeZoneName;
  } catch (_) {
    return 'UTC';
  }
}

final _rnd = math.Random();
const _b36 = '0123456789abcdefghijklmnopqrstuvwxyz';

/// A base-36 timestamp plus five random base-36 characters — the same shape and the same
/// collision odds as `Date.now().toString(36) + Math.random().toString(36).slice(2, 7)`.
String uid() {
  final tail = String.fromCharCodes(
      List.generate(5, (_) => _b36.codeUnitAt(_rnd.nextInt(36))));
  return DateTime.now().millisecondsSinceEpoch.toRadixString(36) + tail;
}
