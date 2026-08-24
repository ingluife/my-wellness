import 'json.dart';

/// How one exercise is planned — a routine entry, and equally the `target` a workout entry
/// carries so a finished session can still say what it prescribed.
///
/// The field set is deliberately sparse. `defaultConfig` writes only what the mode needs, and
/// `exConfigSheet` adds a flag only when it *differs* from what the exercise dataset already
/// says — so a plain barbell config is byte-for-byte what it was before bodyweight and
/// per-side existed, and a shared plan file gains nothing it does not need.
class ExerciseConfig implements HasSuperset {
  ExerciseConfig({
    this.id,
    this.sg,
    this.sets,
    this.reps,
    this.weight,
    this.mode,
    this.min,
    this.speed,
    this.sec,
    this.bodyweight,
    this.side,
    this.repsMin,
    this.repsMax,
    this.prog,
    this.inc,
  });

  /// Exercise id — absent on a bare config passed around inside a sheet.
  String? id;

  /// Superset group. Consecutive entries sharing one form a unit done back-to-back.
  @override
  String? sg;

  double? sets;
  double? reps;
  double? weight;

  /// 'reps' | 'time' | 'cardio'. Absent means "whatever the body part implies", which is how
  /// every plan written before timed exercises existed still reads correctly.
  String? mode;

  double? min;
  double? speed;
  double? sec;

  /// The exercise carries no load of its own, so `w` means *added* weight. Seeded from the
  /// dataset's equipment field and only written when it disagrees with it.
  bool? bodyweight;

  /// Unilateral. You still log the total; the split is derived for display.
  bool? side;

  /// Double progression's floor, and the bodyweight rep ceiling (issue #33).
  double? repsMin;
  double? repsMax;

  /// Per-exercise progression override and load step; absent means "follow the routine".
  String? prog;
  double? inc;

  factory ExerciseConfig.fromJson(Map<String, dynamic> j) => ExerciseConfig(
        id: asStr(j['id']),
        sg: asStr(j['sg']),
        sets: asNum(j['sets']),
        reps: asNum(j['reps']),
        weight: asNum(j['weight']),
        mode: asStr(j['mode']),
        min: asNum(j['min']),
        speed: asNum(j['speed']),
        sec: asNum(j['sec']),
        bodyweight: j['bodyweight'] is bool ? j['bodyweight'] as bool : null,
        side: j['side'] is bool ? j['side'] as bool : null,
        repsMin: asNum(j['repsMin']),
        repsMax: asNum(j['repsMax']),
        prog: asStr(j['prog']),
        inc: asNum(j['inc']),
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    put(m, 'id', id);
    put(m, 'sg', sg);
    putNum(m, 'sets', sets);
    putNum(m, 'reps', reps);
    putNum(m, 'weight', weight);
    put(m, 'mode', mode);
    putNum(m, 'min', min);
    putNum(m, 'speed', speed);
    putNum(m, 'sec', sec);
    put(m, 'bodyweight', bodyweight);
    put(m, 'side', side);
    putNum(m, 'repsMin', repsMin);
    putNum(m, 'repsMax', repsMax);
    put(m, 'prog', prog);
    putNum(m, 'inc', inc);
    return m;
  }

  ExerciseConfig copy() => ExerciseConfig.fromJson(toJson());

  /// A copy carrying [id], for the `{ ...cfg, id }` spread the logic modules do constantly.
  ExerciseConfig withId(String? exId) => copy()..id = exId ?? id;
}
