import '../../data/models/app_state.dart';
import '../format.dart';
import '../history.dart';

/// What went wrong, or nearly did, while reading a drafted plan.
///
/// Shown to the person under the draft, so each case is something they can act on or at least
/// understand. A problem is never a reason to throw the whole draft away — a plan with one
/// invented exercise dropped out of it is still a usable plan.
enum PlanProblem {
  /// The answer was not the agreed shape at all.
  unreadable,

  /// Nothing survived: no routine held a single exercise this build could resolve.
  noRoutines,

  /// At least one id was not in the catalogue. Almost always an invented one.
  unknownExercise,

  /// At least one id resolved but was outside what was asked for — squats in a biceps plan.
  outOfScope,

  /// The same exercise appeared twice in one routine.
  duplicate,

  /// Sets or reps arrived outside anything sensible and were clamped.
  clamped,

  /// More routines or exercises came back than a plan can hold; the tail was dropped.
  tooMany,

  /// A weekday mapping pointed at a routine that does not exist, and was ignored.
  badWeek,
}

/// One exercise in a drafted routine.
class DraftExercise {
  const DraftExercise({
    required this.id,
    required this.name,
    required this.sets,
    required this.reps,
    this.repsMin,
    this.repsMax,
    this.note,
  });

  /// A dataset id that resolved — the sanitiser drops anything that did not, so this is always
  /// an exercise the app can show, animate and progress.
  final String id;

  /// The catalogue name, read from the dataset rather than from the answer. The model is not the
  /// source of truth for what an exercise is called.
  final String name;

  final double sets;
  final double reps;
  final double? repsMin;
  final double? repsMax;

  /// One short line of the model's reasoning for this choice, when it gave one.
  final String? note;

  /// The routine entry this becomes.
  ///
  /// Built on top of [defaultConfig] rather than from scratch, so a drafted exercise carries the
  /// same mode, weight and bodyweight inference a hand-added one does — which is what makes it
  /// behave identically in the workout screen and under progression.
  ExerciseConfig toConfig() => defaultConfig(id)
    ..id = id
    ..sets = sets
    ..reps = reps
    ..repsMin = repsMin
    ..repsMax = repsMax;
}

/// One drafted routine.
class DraftRoutine {
  const DraftRoutine({required this.name, required this.exercises, this.emoji});

  final String name;
  final String? emoji;
  final List<DraftExercise> exercises;

  Routine toRoutine() => Routine(
        id: uid(),
        name: name,
        emoji: emoji,
        ex: [for (final e in exercises) e.toConfig()],
      );
}

/// A plan, as read back and cleaned up, before anything is written.
class PlanDraft {
  const PlanDraft({
    required this.routines,
    this.week = const {},
    this.rationale,
    this.problems = const [],
  });

  PlanDraft.empty(PlanProblem problem)
      : routines = const [],
        week = const {},
        rationale = null,
        problems = [problem];

  final List<DraftRoutine> routines;

  /// Weekday `'0'`..`'6'` to an index into [routines]. Empty for a single-routine draft.
  final Map<String, int> week;

  final String? rationale;
  final List<PlanProblem> problems;

  bool get isEmpty => routines.isEmpty;

  int get exerciseCount =>
      routines.fold(0, (sum, r) => sum + r.exercises.length);
}
