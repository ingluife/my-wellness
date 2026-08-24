import 'json.dart';

/// One weigh-in. `t` is the wall clock it was taken at and is what charts plot against; `d`
/// is the day it belongs to, and there is at most one entry per day.
class BodyWeightEntry {
  BodyWeightEntry({required this.d, required this.w, this.t});

  String d;
  double w;
  int? t;

  factory BodyWeightEntry.fromJson(Map<String, dynamic> j) => BodyWeightEntry(
        d: asStr(j['d']) ?? '',
        w: asNumOr(j['w'], 0),
        t: asNum(j['t'])?.toInt(),
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'d': d, 'w': jsonNum(w)};
    put(m, 't', t);
    return m;
  }

  BodyWeightEntry copy() => BodyWeightEntry.fromJson(toJson());
}

/// The working weight confirmed for an exercise, and when. Seeds the next session's sets and
/// is the number the "confirm your working weight" sheet calls your best.
class ExWeight {
  ExWeight({required this.w, required this.d});

  double w;
  String d;

  factory ExWeight.fromJson(Map<String, dynamic> j) =>
      ExWeight(w: asNumOr(j['w'], 0), d: asStr(j['d']) ?? '');

  Map<String, dynamic> toJson() => {'w': jsonNum(w), 'd': d};

  ExWeight copy() => ExWeight.fromJson(toJson());
}

/// A user-created exercise (issue #11). A name and a body part is all it takes — it then
/// behaves like any built-in one everywhere, just without an animation.
class CustomExercise {
  CustomExercise({
    required this.id,
    required this.n,
    required this.bp,
    this.desc = '',
    this.tg = '',
    this.eq = 'custom',
  });

  final String id;
  String n;
  String bp;
  String desc;
  String tg;
  String eq;

  factory CustomExercise.fromJson(Map<String, dynamic> j) => CustomExercise(
        id: asStr(j['id']) ?? '',
        n: asStr(j['n']) ?? '',
        bp: asStr(j['bp']) ?? '',
        desc: asStr(j['desc']) ?? '',
        tg: asStr(j['tg']) ?? '',
        eq: asStr(j['eq']) ?? 'custom',
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'n': n, 'bp': bp, 'desc': desc, 'tg': tg, 'eq': eq, 'custom': true};

  CustomExercise copy() => CustomExercise.fromJson(toJson());
}

/// The workout-day reminder. `tz` is re-stamped on every launch so the reminder stays correct
/// if you are travelling, without needing to revisit Settings.
class Reminder {
  Reminder({this.on = false, this.time = '08:00', this.tz});

  bool on;
  String time;
  String? tz;

  factory Reminder.fromJson(Map<String, dynamic> j) => Reminder(
        on: asBool(j['on']),
        time: asStr(j['time']) ?? '08:00',
        tz: asStr(j['tz']),
      );

  Map<String, dynamic> toJson() => {'on': on, 'time': time, 'tz': tz};

  Reminder copy() => Reminder.fromJson(toJson());
}
