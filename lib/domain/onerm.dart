import 'dart:math' as math;

import '../data/models/app_state.dart';

/// Estimated one-rep max, ported from lib/onerm.js.
///
/// Deliberately knows nothing about the exercise database: an estimate needs a weight AND a rep
/// count, and only reps-mode sets carry both. Cardio sets (`{min, speed}`) and timed sets
/// (`{sec, w}`) therefore drop out of every scan here on their own — there is no exercise-type
/// check to keep in sync.
///
/// The formulas are the usual submaximal-load estimators. Epley is the default because it is
/// the one most lifters have seen; all of them agree closely at low reps and diverge as reps
/// rise, which is exactly why [repCap] exists.

/// Above this many reps an estimate says more about work capacity than about maximal strength,
/// and the formulas disagree by double digits. Refusing to guess beats printing a fantasy.
const repCap = 12;

const formulas = <String, double Function(double, double)>{
  // Epley 1985 — w · (1 + r/30)
  'epley': _epley,
  // Brzycki 1993 — w · 36/(37 − r); undefined at r >= 37, but repCap is far below that
  'brzycki': _brzycki,
  // Lombardi 1989 — w · r^0.10
  'lombardi': _lombardi,
};

double _epley(double w, double r) => w * (1 + r / 30);
double _brzycki(double w, double r) => w * 36 / (37 - r);
double _lombardi(double w, double r) => w * math.pow(r, 0.1);

const defaultFormula = 'epley';

/// Estimate a 1RM from one set.
///
/// Returns null for anything it cannot honestly answer: missing/zero/negative load, no reps,
/// non-finite input, or more reps than [repCap]. A single rep is not an estimate — it is the
/// measurement — and comes back unchanged.
double? estimate1RM(num? w, num? r, [String formula = defaultFormula]) {
  final weight = w?.toDouble();
  final reps = r?.toDouble();
  if (weight == null || reps == null) return null;
  if (!weight.isFinite || !reps.isFinite) return null;
  if (weight <= 0 || reps < 1) return null;
  if (reps > repCap) return null;
  final fn = formulas[formula] ?? formulas[defaultFormula]!;
  final est = reps == 1 ? weight : fn(weight, reps.roundToDouble());
  if (!est.isFinite || est <= 0) return null;
  return (est * 10).round() / 10;
}

typedef BestSet = ({double est, double w, int r});

/// Best estimate out of one workout entry's completed sets.
///
/// `topW` is ignored on purpose: it records the working weight a user confirmed after the
/// exercise, with no rep count attached, so it cannot produce an estimate.
BestSet? bestSetOf(WorkoutEntry? entry, [String formula = defaultFormula]) {
  BestSet? best;
  for (final s in entry?.sets ?? const <SetLog>[]) {
    if (!s.done) continue;
    final est = estimate1RM(s.w, s.r, formula);
    if (est != null && (best == null || est > best.est)) {
      best = (est: est, w: s.w!.toDouble(), r: s.r!.round());
    }
  }
  return best;
}

typedef E1rmPoint = ({int t, String d, double y, double w, int r});

/// One point per workout in which the exercise produced an estimate — feeds the trend chart.
/// Chronological, matching the order workouts are appended in.
List<E1rmPoint> e1rmSeries(AppState s, String exId, [String formula = defaultFormula]) {
  final pts = <E1rmPoint>[];
  for (final w in s.workouts) {
    for (final e in w.entries) {
      if (e.id != exId) continue;
      final best = bestSetOf(e, formula);
      if (best != null) {
        pts.add((t: w.start, d: w.d, y: best.est, w: best.w, r: best.r));
      }
      break;
    }
  }
  return pts;
}

typedef Best1RM = ({double est, double w, int r, String d, int t});

/// All-time best estimate for an exercise, with the set and date it came from — the source
/// matters, because "142.5 kg est. from 100×10" is a very different claim from "from 140×1".
Best1RM? best1RM(AppState s, String exId, [String formula = defaultFormula]) {
  Best1RM? best;
  for (final p in e1rmSeries(s, exId, formula)) {
    if (best == null || p.y > best.est) {
      best = (est: p.y, w: p.w, r: p.r, d: p.d, t: p.t);
    }
  }
  return best;
}

typedef E1rmRecord = ({double est, double w, int r, double prev});

/// Did this workout beat every estimate that came before it?
///
/// Used for the finish summary, so it compares against history that does not yet contain the
/// session being finished.
E1rmRecord? is1RMRecord(AppState s, String exId, WorkoutEntry entry,
    [String formula = defaultFormula]) {
  final now = bestSetOf(entry, formula);
  if (now == null) return null;
  final prev = best1RM(s, exId, formula);
  return prev == null || now.est > prev.est
      ? (est: now.est, w: now.w, r: now.r, prev: prev?.est ?? 0)
      : null;
}
