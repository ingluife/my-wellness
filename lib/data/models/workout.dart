import 'exercise_config.dart';
import 'json.dart';
import 'prescription.dart';
import 'set_log.dart';

/// One exercise inside a session — running or finished.
class WorkoutEntry implements HasSuperset {
  WorkoutEntry({
    required this.id,
    this.sg,
    this.target,
    this.plan,
    this.topW,
    this.asked = false,
    this.n,
    this.writesTopW = false,
    List<SetLog>? sets,
  }) : sets = sets ?? [];

  final String id;

  /// Superset group, copied from the routine entry.
  @override
  String? sg;

  /// What the session prescribed. Finished workouts carry it so labels and the progression
  /// engine can read a session back the way it was logged; workouts written before v1.2.2
  /// have none, and are judged against the exercise's current plan instead.
  ExerciseConfig? target;

  /// Why the opening numbers are what they are. Not persisted with finished workouts.
  Prescription? plan;

  /// The working weight confirmed after the exercise. No rep count attached, so it never
  /// produces a 1RM estimate.
  double? topW;

  /// Whether `topW` is written even when unset.
  ///
  /// The two places an entry is built disagree, and both spellings have to survive a
  /// round-trip: `doFinishWorkout` writes `topW: e.topW || null`, so every entry in history
  /// carries the key; a running session only gains it once the top-weight sheet is confirmed.
  bool writesTopW;

  /// The top-weight sheet has already been offered for this exercise this session.
  bool asked;

  /// Name stamped in when a custom exercise is deleted, so past workouts stay readable.
  String? n;

  List<SetLog> sets;

  factory WorkoutEntry.fromJson(Map<String, dynamic> j) => WorkoutEntry(
        id: asStr(j['id']) ?? '',
        sg: asStr(j['sg']),
        target: j['target'] is Map ? ExerciseConfig.fromJson(asMap(j['target'])) : null,
        plan: j['plan'] is Map ? Prescription.fromJson(asMap(j['plan'])) : null,
        topW: asNum(j['topW']),
        asked: asBool(j['asked']),
        n: asStr(j['n']),
        writesTopW: j.containsKey('topW'),
        sets: asList(j['sets'], SetLog.fromJson),
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'id': id};
    put(m, 'sg', sg);
    put(m, 'target', target?.toJson());
    put(m, 'plan', plan?.toJson());
    if (writesTopW) {
      m['topW'] = topW == null ? null : jsonNum(topW!);
    } else {
      putNum(m, 'topW', topW);
    }
    if (asked) m['asked'] = true;
    put(m, 'n', n);
    m['sets'] = [for (final s in sets) s.toJson()];
    return m;
  }

  WorkoutEntry copy() => WorkoutEntry.fromJson(toJson());

  /// The config the logic modules read: the target, carrying this entry's exercise id.
  ExerciseConfig get cfg => (target?.copy() ?? ExerciseConfig())..id = id;
}

/// A session in progress. Exactly one exists at a time, and it is persisted like everything
/// else — closing the app mid-workout loses nothing.
class ActiveWorkout {
  ActiveWorkout({
    required this.id,
    required this.d,
    required this.start,
    this.routineId,
    required this.name,
    this.bw,
    this.cur = 0,
    List<WorkoutEntry>? entries,
  }) : entries = entries ?? [];

  final String id;
  String d;
  int start;
  String? routineId;
  String name;

  /// The weigh-in taken before the session started, or null if it was skipped.
  double? bw;

  /// Index of the entry currently on screen. Prev/Next moves by superset *unit*, so this can
  /// only ever be the first index of a unit.
  int cur;

  List<WorkoutEntry> entries;

  factory ActiveWorkout.fromJson(Map<String, dynamic> j) => ActiveWorkout(
        id: asStr(j['id']) ?? '',
        d: asStr(j['d']) ?? '',
        start: asNumOr(j['start'], 0).toInt(),
        routineId: asStr(j['routineId']),
        name: asStr(j['name']) ?? '',
        bw: asNum(j['bw']),
        cur: asNumOr(j['cur'], 0).toInt(),
        entries: asList(j['entries'], WorkoutEntry.fromJson),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'd': d,
        'start': start,
        'routineId': routineId,
        'name': name,
        'bw': bw == null ? null : jsonNum(bw!),
        'cur': cur,
        'entries': [for (final e in entries) e.toJson()],
      };

  ActiveWorkout copy() => ActiveWorkout.fromJson(toJson());
}

/// A finished session, appended to history and never edited again.
class Workout {
  Workout({
    required this.id,
    required this.d,
    required this.start,
    required this.end,
    this.routineId,
    required this.name,
    this.bw,
    this.vol,
    List<String>? prs,
    List<WorkoutEntry>? entries,
  })  : prs = prs ?? [],
        entries = entries ?? [];

  final String id;
  String d;
  int start;
  int end;
  String? routineId;
  String name;
  double? bw;

  /// Total volume in the profile's unit at the time it was logged.
  double? vol;

  /// Exercise ids that set a new best weight in this session.
  List<String> prs;

  List<WorkoutEntry> entries;

  factory Workout.fromJson(Map<String, dynamic> j) => Workout(
        id: asStr(j['id']) ?? '',
        d: asStr(j['d']) ?? '',
        start: asNumOr(j['start'], 0).toInt(),
        end: asNumOr(j['end'], 0).toInt(),
        routineId: asStr(j['routineId']),
        name: asStr(j['name']) ?? '',
        bw: asNum(j['bw']),
        vol: asNum(j['vol']),
        prs: j['prs'] is List ? [for (final p in j['prs'] as List) if (p is String) p] : [],
        entries: asList(j['entries'], WorkoutEntry.fromJson),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'd': d,
        'start': start,
        'end': end,
        'routineId': routineId,
        'name': name,
        'bw': bw == null ? null : jsonNum(bw!),
        'vol': vol == null ? null : jsonNum(vol!),
        'prs': prs,
        'entries': [for (final e in entries) e.toJson()],
      };

  Workout copy() => Workout.fromJson(toJson());
}
