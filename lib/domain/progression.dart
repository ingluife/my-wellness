import 'dart:math' as math;

import '../data/models/app_state.dart';
import 'exercises.dart';
import 'history.dart';

/// Automatic progression, ported from lib/progression.js.
///
/// Everything here is a pure function of the workout history. Nothing writes back into a
/// finished workout: the log is what happened, and the next prescription is *derived* from it
/// every time it is needed. That means changing a policy — or fixing a mistyped set —
/// immediately produces the right next target, with no stored counters to drift out of sync.
///
/// Reading a session honestly is the whole game:
///   · a set checked off with at least its target reps  -> hit
///   · a set checked off with fewer reps                -> miss (you logged what you got)
///   · a set never checked off                          -> miss (it was not performed)
///   · fewer sets than prescribed                       -> miss
/// So a session that fell apart can never advance the load as though it had succeeded.

const policies = ['off', 'linear', 'greyskull', 'double', 'time'];

/// Which policies can sensibly drive which logging mode.
const policiesFor = <String, List<String>>{
  'reps': ['off', 'linear', 'greyskull', 'double'],
  'time': ['off', 'time'],
  'cardio': ['off'],
};

const policyName = <String, String>{
  'off': 'No automatic progression',
  'linear': 'Linear progression',
  'greyskull': 'Greyskull LP',
  'double': 'Double progression',
  'time': 'Add time',
};

const policyDesc = <String, String>{
  'off': 'Targets stay where you set them.',
  'linear': 'Hit every rep in every set and the weight goes up. Repeated misses trigger a deload.',
  'greyskull': 'Two straight sets plus a final set taken to failure. Beat the target on that set and the weight goes up — double if you double the reps. One failure resets 10 %.',
  'double': 'Work up through a rep range at the same weight. Reach the top of the range in every set and the weight goes up, reps back to the bottom.',
  'time': 'Hold every set for the full duration and the target goes up.',
};

/// Sessions of repeated misses before a deload. Greyskull resets on the first failure by
/// design; the general linear policy gives you two more cracks at it first.
const deloadAfter = <String, int>{'linear': 3, 'greyskull': 1, 'double': 3, 'time': 3};
const _deloadFactor = 0.9;

/// Body parts where a 5 kg jump is normal rather than brutal.
const _heavyBp = ['upper legs', 'lower legs', 'back', 'hips', 'glutes'];

/// Default load step. Lower-body lifts take the bigger jump — that is the "lift-specific
/// increment" a linear program lives on; an exercise can override it with `cfg.inc`.
double defaultIncrement(String? exId, String unit) {
  final ex = exdb[exId];
  final heavy = ex != null && _heavyBp.contains(ex.bp);
  if (unit == 'lb') return heavy ? 10 : 5;
  return heavy ? 5 : 2.5;
}

const defaultSecIncrement = 5.0;

/// Where adding another set of push-ups stops being progress and starts being a way to spend
/// an evening. Past this the honest advice is load or a harder variation.
const maxBwSets = 6;

/// The policy in force for one exercise: its own override, else the routine's default, else
/// the mode's default. Reps keeps behaving the way the app always did (all reps -> add a step).
String policyFor(ExerciseConfig? cfg, Routine? routine, [String? mode]) {
  final m = mode ?? modeOf(cfg);
  final allowed = policiesFor[m] ?? const ['off'];
  final pick = cfg?.prog ?? routine?.prog ?? (m == 'reps' ? 'linear' : 'off');
  return allowed.contains(pick) ? pick : 'off';
}

double _round1(double v) => (v * 10).round() / 10;

/// Snap to a loadable multiple of the step.
double _snap(double v, double step) =>
    step > 0 ? _round1((v / step).round() * step) : _round1(v);

/// Back off by [_deloadFactor], landing on something you can actually load.
///
/// Rounding to the nearest step keeps the cut close to the intended 10 %, but on small weights
/// the nearest step can be the weight you started from — so a deload that did not actually
/// reduce anything takes one step down instead. Never goes below a single step.
double _deloadTo(double cur, double step) {
  var next = _snap(cur * _deloadFactor, step);
  if (next >= cur) next = _snap(cur - step, step);
  return math.max(step, next);
}

/// One finished workout entry, reduced to what a policy needs to judge it.
typedef Session = ({
  String d,
  String mode,
  double goal,
  List<double> reps,
  List<double> held,
  double weight,
  int count,
  double low,
  double amrap,
  double best,
  bool ok,
});

/// Reduce one finished workout entry to what a policy needs to judge it.
///
/// Workouts only started recording their prescription in v1.2.2, so most existing history has
/// no `target` at all. Judging those against nothing would score every past session as a miss —
/// and then greet a long-standing user with "missed reps 11 sessions running, deload". So an
/// entry without its own target is judged against [fallback], the exercise's current plan,
/// which is exactly what the app's old weight hint compared against.
Session readSession(WorkoutEntry? entry, ExerciseConfig? fallback, {String d = ''}) {
  final target = entry?.target ?? fallback ?? ExerciseConfig();
  final mode = modeOf(target.withId(entry?.id));
  final sets = entry?.sets ?? const <SetLog>[];
  final planned = (target.sets ?? sets.length).round();
  final enough = sets.length >= planned;
  final weight = sets.where((s) => s.done).fold(0.0, (a, s) => math.max(a, s.w ?? 0));

  if (mode == 'time') {
    final goal = target.sec ?? 0;
    final held = [for (final s in sets) s.done ? (s.sec ?? 0) : 0.0];
    return (
      d: d,
      mode: mode,
      goal: goal,
      reps: const [],
      held: held,
      weight: weight,
      count: held.length,
      low: held.isEmpty ? 0 : held.reduce(math.min),
      amrap: held.isEmpty ? 0 : held.last,
      best: held.fold(0.0, math.max),
      ok: goal > 0 && enough && held.isNotEmpty && held.every((h) => h >= goal),
    );
  }
  final goal = target.reps ?? 0;
  final reps = [for (final s in sets) s.done ? (s.r ?? 0) : 0.0];
  return (
    d: d,
    mode: mode,
    goal: goal,
    reps: reps,
    held: const [],
    weight: weight,
    // The dimension bodyweight work grows.
    count: reps.length,
    low: reps.isEmpty ? 0 : reps.reduce(math.min),
    // Greyskull's final set.
    amrap: reps.isEmpty ? 0 : reps.last,
    best: reps.fold(0.0, math.max),
    ok: goal > 0 && enough && reps.isNotEmpty && reps.every((r) => r >= goal),
  );
}

/// Every past session for one exercise, oldest first. [fallback] — see [readSession].
List<Session> sessionsFor(AppState s, String exId, ExerciseConfig? fallback) {
  final out = <Session>[];
  for (final w in s.workouts) {
    for (final e in w.entries) {
      if (e.id == exId && e.sets.any((x) => x.done)) {
        out.add(readSession(e, fallback, d: w.d));
        break;
      }
    }
  }
  return out;
}

/// How many sessions in a row ended in a miss, counting back from the most recent.
int stallCount(List<Session> sessions) {
  var n = 0;
  for (var i = sessions.length - 1; i >= 0; i--) {
    if (sessions[i].ok) break;
    n++;
  }
  return n;
}

/// The next prescription for one exercise.
///
/// `kind` is one of first | up | hold | deload | off, and `why` a translatable template plus
/// its arguments, so the app can always answer "why this number?". A field the policy has no
/// opinion on comes back null and the caller keeps whatever the plan said.
Prescription nextPrescription(AppState s, ExerciseConfig cfg, Routine? routine) {
  final mode = modeOf(cfg);
  final policy = policyFor(cfg, routine, mode);
  final unit = s.unit;
  final inc = (cfg.inc ?? 0) > 0
      ? cfg.inc!
      : (mode == 'time' ? defaultSecIncrement : defaultIncrement(cfg.id, unit));
  if (policy == 'off') return Prescription(policy: policy, kind: 'off');

  final sessions = sessionsFor(s, cfg.id ?? '', cfg).where((x) => x.mode == mode).toList();
  if (sessions.isEmpty) {
    return Prescription(
        policy: policy,
        kind: 'first',
        why: ['Nothing logged yet — this session sets the baseline.']);
  }
  final last = sessions.last;
  final stalls = stallCount(sessions);
  final deloadAt = deloadAfter[policy] ?? 3;

  if (mode == 'time') {
    if (last.ok) {
      final sec = (last.goal > 0 ? last.goal : (cfg.sec ?? 0)) + inc;
      return Prescription(policy: policy, kind: 'up', sec: sec, why: [
        'Held every set for the full time — target up by {0}s.',
        inc
      ]);
    }
    if (stalls >= deloadAt) {
      final sec = _deloadTo(last.goal > 0 ? last.goal : (cfg.sec ?? 0), 5);
      return Prescription(policy: policy, kind: 'deload', sec: sec, why: [
        'Short {0} sessions in a row — back off to {1}s and build up again.',
        stalls,
        sec
      ]);
    }
    return Prescription(
        policy: policy,
        kind: 'hold',
        sec: last.goal > 0 ? last.goal : cfg.sec,
        why: ['Last time came up short — same target again.']);
  }

  final w = last.weight;
  // Bodyweight work carries no external load, so there is nothing to add or take away —
  // "deload your push-ups to 2.5 kg" is not advice. Progress in reps instead. This runs ahead
  // of the individual policies because it is true for all of them. Note the trigger is the
  // *logged* weight, not the bodyweight flag: a dip done with a belt has a load to progress
  // and belongs on the normal policies, and a barbell lift logged at 0 has nothing to add to.
  if (w <= 0) {
    final goal = last.goal > 0 ? last.goal : (cfg.reps ?? 0);
    if (!last.ok || goal <= 0) {
      return Prescription(
          policy: policy,
          kind: 'hold',
          weight: 0,
          reps: goal > 0 ? goal : null,
          why: ['Bodyweight — same target again until every set is clean.']);
    }
    // A ceiling turns "+1 rep forever" into a plan. Past the top of the range the reps go back
    // to the bottom and a set is added instead, which is how bodyweight work actually
    // progresses once a set of 30 push-ups stops being a strength stimulus.
    final top = (cfg.repsMax ?? 0) > 0 ? cfg.repsMax! : 0.0;
    if (top > 0 && goal >= top) {
      final sets = math.max(1.0, cfg.sets ?? last.count.toDouble()) + 1;
      final bottom = math.max(1.0, math.min(cfg.reps ?? top, top));
      if (sets <= maxBwSets) {
        return Prescription(policy: policy, kind: 'up', weight: 0, reps: bottom, sets: sets, why: [
          '{0} reps in every set — add a set and go back to {1}.',
          goal,
          bottom
        ]);
      }
      // Out of sets worth adding: more volume is no longer the answer, load or a harder
      // variation is — and that is a decision for a person, not a policy.
      return Prescription(policy: policy, kind: 'hold', weight: 0, reps: goal, why: [
        '{0} sets of {1} — time to add weight or move to a harder variation.',
        sets - 1,
        goal
      ]);
    }
    // Unilateral work steps by two, so the total stays even and both sides get the rep.
    final next = goal + repStep(cfg);
    return Prescription(policy: policy, kind: 'up', weight: 0, reps: next, why: [
      'Bodyweight — every rep last time, so go for {0} this time.',
      next
    ]);
  }

  if (policy == 'double') {
    final top = cfg.reps ?? (last.goal > 0 ? last.goal : 10);
    final bottom = math.min(cfg.repsMin ?? math.max(1.0, top - 2), top);
    if (last.ok) {
      return Prescription(
          policy: policy,
          kind: 'up',
          weight: _snap(w + inc, inc),
          reps: bottom,
          why: ['Top of the rep range in every set — {0} {1} more, back to {2} reps.', inc, unit, bottom]);
    }
    if (stalls >= deloadAt) {
      final dw = _deloadTo(w, inc);
      return Prescription(
          policy: policy,
          kind: 'deload',
          weight: dw,
          reps: bottom,
          why: ['Stalled {0} sessions — deload to {1} {2}.', stalls, dw, unit]);
    }
    final aim = math.min(top, math.max(bottom, last.low + repStep(cfg)));
    return Prescription(
        policy: policy,
        kind: 'hold',
        weight: w,
        reps: aim,
        why: ['Same weight — aim for {0} reps this time.', aim]);
  }

  // linear + greyskull
  if (last.ok) {
    // Greyskull's final set is taken to failure: double the target reps there and you have
    // earned a double jump.
    final dbl = policy == 'greyskull' && last.goal > 0 && last.amrap >= last.goal * 2;
    final step = dbl ? inc * 2 : inc;
    return Prescription(
        policy: policy,
        kind: 'up',
        weight: _snap(w + step, inc),
        why: dbl
            ? ['Last set hit {0} reps — twice the target, so take a double jump of {1} {2}.', last.amrap, step, unit]
            : ['Every rep last time — {0} {1} more.', step, unit]);
  }
  if (stalls >= deloadAt) {
    final dw = _deloadTo(w, inc);
    return Prescription(
        policy: policy,
        kind: 'deload',
        weight: dw,
        why: stalls > 1
            ? ['Missed reps {0} sessions running — reset to {1} {2} and work back up.', stalls, dw, unit]
            : ['Missed reps — reset to {0} {1} and work back up.', dw, unit]);
  }
  return Prescription(
      policy: policy,
      kind: 'hold',
      weight: w,
      why: ['Missed reps last time — same weight again ({0} of {1} to go).', deloadAt - stalls, deloadAt]);
}

/// Apply a prescription to freshly built sets. Only the fields the policy actually decided are
/// touched, and only on sets that have not been logged yet.
List<SetLog> applyPrescription(List<SetLog> sets, Prescription? p) {
  if (p == null || p.kind == 'off' || p.kind == 'first') return sets;
  final out = [
    for (final s in sets)
      if (s.done)
        s
      else
        (s.copy()
          ..w = p.weight ?? s.w
          ..r = p.reps ?? s.r
          ..sec = p.sec ?? s.sec)
  ];
  // A policy that decided on a set count gets to grow the list — bodyweight progression adds a
  // set where a barbell would have added a plate. Only ever upwards, and only by copying a row
  // that is already there: a session in progress must not lose a set it has logged.
  final want = (p.sets ?? 0).round();
  if (want > out.length && out.isNotEmpty) {
    final seed = out.last;
    while (out.length < want) {
      out.add(seed.copy()..done = false);
    }
  }
  return out;
}
