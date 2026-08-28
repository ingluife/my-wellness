import '../exercises.dart';
import 'plan_draft.dart';
import 'plan_scope.dart';

/// Turns what a model said into a plan the app is willing to show, and eventually to save.
///
/// Pure: no Flutter, no I/O, no globals. The catalogue lookup arrives as a function rather than
/// through `exdb[id]` because `Exercises` loads from `rootBundle`, and reaching for it here would
/// drag a Flutter test binding into every bounds check in this file.
///
/// The rule this whole file exists to enforce: **a routine is built from catalogue ids, never
/// from anything a model wrote.** The model chooses *which* exercises and *how many* sets; the
/// name, body part, target, equipment, animation and progression behaviour all come from the
/// dataset. An id that does not resolve is dropped rather than turned into a placeholder — a
/// routine holding an exercise the app cannot show or progress is worse than a shorter one.
typedef ExerciseLookup = Exercise? Function(String id);

/// The most routines one plan can hold. A week has seven days, and a split with more distinct
/// sessions than that is not a week.
const _maxRoutines = 7;

/// The most exercises one routine can hold.
///
/// A session someone will actually finish is well under this. A model returning twenty has
/// started listing everything that touches the muscle rather than choosing.
const _maxExercises = 12;

/// Bounds on a prescription. Wide on purpose — these exist to catch a model that returned 0 or
/// 500, not to second-guess a defensible 5x5 or 4x20.
const _minSets = 1.0;
const _maxSets = 10.0;
const _minReps = 1.0;
const _maxReps = 50.0;

PlanDraft sanitizePlanDraft(
  Object? raw, {
  required ExerciseLookup lookup,
  required PlanScope scope,
}) {
  // 1. Envelope. Anything that is not the agreed shape is a failure to read, not a crash — this
  //    function is called on whatever a third party returned and must never throw.
  if (raw is! Map) return PlanDraft.empty(PlanProblem.unreadable);
  final map = Map<String, dynamic>.from(raw);

  final rawRoutines = map['routines'];
  if (rawRoutines is! List || rawRoutines.isEmpty) {
    return PlanDraft.empty(PlanProblem.noRoutines);
  }

  final problems = <PlanProblem>{};

  // 2. Cap the routines, keeping the first: unlike a meal's items these are ordered by the
  //    model's own intent, so the tail is what it considered least important.
  var entries = [
    for (final r in rawRoutines)
      if (r is Map) Map<String, dynamic>.from(r)
  ];
  if (entries.length > _maxRoutines) {
    problems.add(PlanProblem.tooMany);
    entries = entries.take(_maxRoutines).toList();
  }

  final routines = <DraftRoutine>[];
  for (final e in entries) {
    final routine = _routine(e, lookup, scope, problems);
    // A routine that lost every exercise is not a routine. Dropping it here is what keeps
    // `week` honest below, since the indices are into what survived.
    if (routine != null) routines.add(routine);
  }

  if (routines.isEmpty) {
    return PlanDraft(
      routines: const [],
      problems: {...problems, PlanProblem.noRoutines}.toList(),
    );
  }

  return PlanDraft(
    routines: routines,
    week: _week(map['week'], routines.length, problems),
    rationale: _text(map['rationale'], max: 400),
    problems: problems.toList(),
  );
}

DraftRoutine? _routine(
  Map<String, dynamic> e,
  ExerciseLookup lookup,
  PlanScope scope,
  Set<PlanProblem> problems,
) {
  final rawEx = e['exercises'];
  if (rawEx is! List) return null;

  final exercises = <DraftExercise>[];
  final seen = <String>{};

  for (final item in rawEx) {
    if (item is! Map) continue;
    final id = _text(item['id'], max: 40);
    if (id == null) continue;

    // 3. The load-bearing check. An id the dataset does not carry is an invention, and there is
    //    nothing useful to do with it: no name, no animation, no body part for progression.
    final ex = lookup(id);
    if (ex == null) {
      problems.add(PlanProblem.unknownExercise);
      continue;
    }

    // 4. In scope. A model asked for biceps that returns a squat has not answered the question,
    //    and the person would have to delete it by hand. The scope was already applied to the
    //    catalogue it was given, so anything failing here was invented or misread.
    if (!scope.includes(ex)) {
      problems.add(PlanProblem.outOfScope);
      continue;
    }

    // 5. One appearance each. `addMealItem`'s equivalent merges duplicates; here the second copy
    //    is simply wrong — nobody programs the same movement twice in one session by accident.
    if (!seen.add(id)) {
      problems.add(PlanProblem.duplicate);
      continue;
    }

    if (exercises.length >= _maxExercises) {
      problems.add(PlanProblem.tooMany);
      break;
    }

    final sets = _clamp(item['sets'], _minSets, _maxSets, 3, problems);
    final reps = _clamp(item['reps'], _minReps, _maxReps, 10, problems);
    final repsMin = _optional(item['repsMin'], _minReps, _maxReps);
    final repsMax = _optional(item['repsMax'], _minReps, _maxReps);

    exercises.add(DraftExercise(
      id: id,
      // From the dataset, never from the answer — see this file's opening note.
      name: ex.n,
      sets: sets,
      reps: reps,
      // A range only survives if it is one: a floor above its ceiling is dropped rather than
      // swapped, because which of the two the model meant is not knowable.
      repsMin: repsMin != null && repsMax != null && repsMin > repsMax ? null : repsMin,
      repsMax: repsMin != null && repsMax != null && repsMin > repsMax ? null : repsMax,
      note: _text(item['note'], max: 160),
    ));
  }

  if (exercises.isEmpty) return null;

  return DraftRoutine(
    name: _text(e['name'], max: 40) ?? 'Routine',
    emoji: _text(e['emoji'], max: 20),
    exercises: exercises,
  );
}

/// The weekday map, keeping only entries that point at a routine that exists.
///
/// Indices are into the routines that *survived*, and a plan that lost one to invented ids would
/// otherwise map a weekday onto the wrong session — or off the end of the list.
Map<String, int> _week(Object? raw, int count, Set<PlanProblem> problems) {
  if (raw is! Map) return const {};
  final out = <String, int>{};
  for (final entry in raw.entries) {
    final day = entry.key;
    if (day is! String || !const {'0', '1', '2', '3', '4', '5', '6'}.contains(day)) {
      problems.add(PlanProblem.badWeek);
      continue;
    }
    final idx = entry.value;
    if (idx is! num || idx < 0 || idx >= count || idx != idx.roundToDouble()) {
      problems.add(PlanProblem.badWeek);
      continue;
    }
    out[day] = idx.toInt();
  }
  return out;
}

double _clamp(Object? v, double lo, double hi, double fallback, Set<PlanProblem> problems) {
  if (v is! num || v.isNaN || v.isInfinite) {
    problems.add(PlanProblem.clamped);
    return fallback;
  }
  final rounded = v.toDouble().roundToDouble();
  if (rounded < lo || rounded > hi) {
    problems.add(PlanProblem.clamped);
    return rounded.clamp(lo, hi);
  }
  return rounded;
}

double? _optional(Object? v, double lo, double hi) {
  if (v is! num || v.isNaN || v.isInfinite) return null;
  final rounded = v.toDouble().roundToDouble();
  return rounded < lo || rounded > hi ? null : rounded;
}

/// A trimmed, length-capped string, or null when there is nothing usable.
///
/// The cap is not cosmetic: every one of these is rendered into a row, and a model that returned
/// a paragraph where a name belongs would push the rest of the sheet off the screen.
String? _text(Object? v, {required int max}) {
  if (v is! String) return null;
  final s = v.trim();
  if (s.isEmpty) return null;
  return s.length <= max ? s : s.substring(0, max).trimRight();
}
