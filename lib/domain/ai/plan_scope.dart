import '../exercises.dart';

/// How much of the catalogue a plan request is about.
///
/// This is the feature's main cost control, and the reason it is a filter rather than a sentence
/// in the prompt. The whole projected catalogue is ~19,000 tokens; one target muscle is ~2,400.
/// Asking the model in prose to "only pick biceps exercises" would pay for all 1,293 either way
/// and still leave it free to wander — filtering first makes the wandering impossible and the
/// request eight times cheaper.
sealed class PlanScope {
  const PlanScope();

  /// Everything the app trains for, which is not everything in the dataset — see [_excludedBp].
  const factory PlanScope.fullBody() = FullBodyScope;

  /// One `bp` value: 'upper arms', 'chest', 'upper legs'.
  const factory PlanScope.bodyPart(String bp) = BodyPartScope;

  /// One `tg` value: 'biceps', 'hamstrings', 'lats'.
  const factory PlanScope.target(String tg) = TargetScope;

  /// The label this scope goes by in the prompt. English, like everything else the model reads.
  String get label;

  /// Whether [e] is in scope. The one place the rule lives, so the prompt builder and the
  /// sanitiser cannot disagree about it — which they would eventually, and silently.
  bool includes(Exercise e);
}

/// Cardio and neck are dropped from a full-body plan.
///
/// Not a judgement about either: cardio is programmed by time and intensity rather than by sets
/// and reps and does not survive a "3x10" prescription, and the two neck exercises would be a
/// strange thing to have appear in a general plan nobody asked for it in. Both are still
/// reachable when asked for by name, which is what the body-part scopes are for.
const _excludedBp = {'cardio', 'neck'};

class FullBodyScope extends PlanScope {
  const FullBodyScope();

  @override
  String get label => 'full body';

  @override
  bool includes(Exercise e) => !_excludedBp.contains(e.bp);
}

class BodyPartScope extends PlanScope {
  const BodyPartScope(this.bp);

  final String bp;

  @override
  String get label => bp;

  @override
  bool includes(Exercise e) => e.bp == bp;
}

class TargetScope extends PlanScope {
  const TargetScope(this.tg);

  final String tg;

  @override
  String get label => tg;

  /// Matches the target muscle, and also anything that lists it as a secondary. A biceps day
  /// built only from `tg == 'biceps'` would exclude every chin-up and row in the library, which
  /// is not what somebody asking for one means.
  @override
  bool includes(Exercise e) => e.tg == tg || e.sm.contains(tg);
}

/// Every exercise [scope] admits, in dataset order.
///
/// Dataset order, not sorted: it is stable across runs and across profiles, so two people asking
/// the same question send the same bytes. Custom exercises are deliberately absent — they carry
/// no `tg` and an `eq` of 'custom', so they cannot be scoped or reasoned about, and a model
/// cannot say anything useful about an exercise it only knows the name of.
List<Exercise> exercisesInScope(PlanScope scope, {Set<String>? equipment}) => [
      for (final e in exdb.db)
        if (scope.includes(e) && (equipment == null || equipment.contains(e.eq))) e,
    ];
