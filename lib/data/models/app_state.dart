import 'entries.dart';
import 'json.dart';
import 'nutrition.dart';
import 'routine.dart';
import 'workout.dart';

export 'entries.dart';
export 'exercise_config.dart';
export 'json.dart';
export 'nutrition.dart';
export 'prescription.dart';
export 'routine.dart';
export 'set_log.dart';
export 'workout.dart';

/// The whole persisted state — `S` in useStore.js, and the single object every feature in the
/// app is a pure function of.
///
/// The JSON shape is reproduced exactly, key for key, so a backup exported here imports into
/// openGym and back again with nothing lost. That is not incidental tidiness: it is the
/// property that makes this a translation of the app rather than a lookalike.
class AppState {
  AppState({
    this.unit = 'kg',
    this.restSec = 90,
    this.sound = true,
    this.keepAwake = true,
    this.lang = 'en',
    this.theme = 'dark',
    this.accent = 'lime',
    this.body = 'male',
    this.targetW,
    this.gifSize = 'full',
    this.effort,
    this.showRir,
    Reminder? reminder,
    List<BodyWeightEntry>? bodyweight,
    List<Routine>? routines,
    Map<String, String>? week,
    Map<String, String>? dayPlan,
    Map<String, ExWeight>? exWeights,
    List<Workout>? workouts,
    this.active,
    List<CustomExercise>? customEx,
    Nutrition? nutrition,
    List<Meal>? meals,
    this.ts,
    Map<String, dynamic>? extra,
  })  : reminder = reminder ?? Reminder(),
        bodyweight = bodyweight ?? [],
        routines = routines ?? [],
        week = week ?? {},
        dayPlan = dayPlan ?? {},
        exWeights = exWeights ?? {},
        workouts = workouts ?? [],
        customEx = customEx ?? [],
        nutrition = nutrition ?? Nutrition(),
        meals = meals ?? [],
        extra = extra ?? {};

  /// 'kg' | 'lb'. A label only — switching it never converts logged numbers.
  String unit;
  double restSec;
  bool sound;
  bool keepAwake;
  String lang;
  String theme;
  String accent;

  /// Which figure the muscle map draws: 'male' | 'female'. Nothing else reads it.
  String body;

  /// Target body weight, drawn as a line through the weight charts.
  double? targetW;

  /// 'full' | 'mini' — the exercise animation size chosen in the workout view.
  String gifSize;

  /// Which per-set effort scale is logged: null | 'none' | 'rir' | 'rpe'.
  ///
  /// null, not 'none', so a profile that never chose still falls back to [showRir], the
  /// boolean this replaced, and keeps the column it had. An explicit 'none' has to win over
  /// that boolean — see `effortOf`.
  String? effort;

  /// Legacy flag [effort] replaced. Kept so a backup or another device still carrying it is
  /// read the way it expects.
  bool? showRir;

  Reminder reminder;

  List<BodyWeightEntry> bodyweight;
  List<Routine> routines;

  /// Weekday -> routine id, keyed by `getDay()` as a string: '0' is Sunday.
  Map<String, String> week;

  /// ISO date -> routine id, or the literal 'rest'. Overrides [week] for that one day.
  Map<String, String> dayPlan;

  /// Exercise id -> the working weight last confirmed for it.
  Map<String, ExWeight> exWeights;

  List<Workout> workouts;
  ActiveWorkout? active;
  List<CustomExercise> customEx;

  /// Body profile and calorie goal. Not a key openGym knows — see the doc on [Nutrition].
  Nutrition nutrition;

  /// The food log, one entry per meal, in the order they were logged.
  List<Meal> meals;

  /// `_ts` — last write, and the tiebreaker when a synced copy and a local one disagree.
  int? ts;

  /// Top-level keys this build does not know about, carried through untouched.
  ///
  /// Without this, importing a backup from a newer openGym and exporting it again would
  /// quietly drop whatever it added. Round-tripping data you do not understand is the
  /// difference between a backup and a lossy conversion.
  Map<String, dynamic> extra;

  static const _known = {
    'unit', 'restSec', 'sound', 'keepAwake', 'lang', 'theme', 'accent', 'body', 'targetW',
    'gifSize', 'effort', 'showRir', 'reminder', 'bodyweight', 'routines', 'week', 'dayPlan',
    'exWeights', 'workouts', 'active', 'customEx', 'nutrition', 'meals', '_ts',
  };

  /// `DEF` from useStore.js.
  factory AppState.defaults() => AppState();

  factory AppState.fromJson(Map<String, dynamic> j) {
    final s = AppState(
      unit: asStr(j['unit']) ?? 'kg',
      restSec: asNumOr(j['restSec'], 90),
      sound: asBool(j['sound'], fallback: true),
      keepAwake: asBool(j['keepAwake'], fallback: true),
      lang: asStr(j['lang']) ?? 'en',
      theme: asStr(j['theme']) ?? 'dark',
      accent: asStr(j['accent']) ?? 'lime',
      body: asStr(j['body']) ?? 'male',
      targetW: asNum(j['targetW']),
      gifSize: asStr(j['gifSize']) ?? 'full',
      effort: asStr(j['effort']),
      showRir: j['showRir'] is bool ? j['showRir'] as bool : null,
      reminder: j['reminder'] is Map ? Reminder.fromJson(asMap(j['reminder'])) : Reminder(),
      bodyweight: asList(j['bodyweight'], BodyWeightEntry.fromJson),
      routines: asList(j['routines'], Routine.fromJson),
      week: {
        for (final e in asMap(j['week']).entries)
          if (e.value is String && (e.value as String).isNotEmpty) e.key: e.value as String
      },
      dayPlan: {
        for (final e in asMap(j['dayPlan']).entries)
          if (e.value is String) e.key: e.value as String
      },
      exWeights: {
        for (final e in asMap(j['exWeights']).entries)
          if (e.value is Map) e.key: ExWeight.fromJson(Map<String, dynamic>.from(e.value as Map))
      },
      workouts: asList(j['workouts'], Workout.fromJson),
      active: j['active'] is Map ? ActiveWorkout.fromJson(asMap(j['active'])) : null,
      customEx: asList(j['customEx'], CustomExercise.fromJson),
      nutrition: j['nutrition'] is Map ? Nutrition.fromJson(asMap(j['nutrition'])) : null,
      meals: asList(j['meals'], Meal.fromJson),
      ts: asNum(j['_ts'])?.toInt(),
    );
    for (final e in j.entries) {
      if (!_known.contains(e.key)) s.extra[e.key] = e.value;
    }
    return s;
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'unit': unit,
      'restSec': jsonNum(restSec),
      'sound': sound,
      'keepAwake': keepAwake,
      'lang': lang,
      'theme': theme,
      'accent': accent,
      'body': body,
      'targetW': targetW == null ? null : jsonNum(targetW!),
      'bodyweight': [for (final b in bodyweight) b.toJson()],
      'routines': [for (final r in routines) r.toJson()],
      'week': week,
      'dayPlan': dayPlan,
      'exWeights': {for (final e in exWeights.entries) e.key: e.value.toJson()},
      'workouts': [for (final w in workouts) w.toJson()],
      'active': active?.toJson(),
      'customEx': [for (final c in customEx) c.toJson()],
      'gifSize': gifSize,
      'reminder': reminder.toJson(),
      'effort': effort,
    };
    // Only ever written when a profile still carries it — see [showRir].
    put(m, 'showRir', showRir);
    // Both are absent until the feature is used, so a profile that never opened Nutrition still
    // exports exactly the JSON openGym does. Writing them unconditionally would put two keys it
    // has no default for into every backup and break the round-trip the whole model is built on.
    put(m, 'nutrition', nutrition.isDefault ? null : nutrition.toJson());
    if (meals.isNotEmpty) m['meals'] = [for (final x in meals) x.toJson()];
    put(m, '_ts', ts);
    m.addAll(extra);
    return m;
  }

  /// The deep clone `update()` mutates, matching `clone(get().S)` in useStore.js.
  AppState copy() => AppState.fromJson(deepCopyJson(toJson()));

  /// `hasData(st)` — is there anything here worth protecting from being overwritten by a sync?
  bool get hasData =>
      workouts.isNotEmpty || routines.isNotEmpty || bodyweight.isNotEmpty;
}
