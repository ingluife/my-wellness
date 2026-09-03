import 'dart:math' as math;

import '../data/models/app_state.dart';
import 'effort.dart';
import 'exercises.dart';
import 'history.dart';

/// How hard an exercise works you, as a multiple of sitting still.
///
/// One MET is resting metabolism — roughly 1 kcal per kg of body weight per hour. Everything
/// here is read off the Compendium of Physical Activities, the standard reference epidemiology
/// uses, rather than invented: the numbers are estimates either way, but they are estimates
/// somebody else has already validated against indirect calorimetry.
///
/// The dataset carries no MET, no duration and no intensity (`assets/data/exercises.json` has
/// exactly `bp eq gif id img mg n sm st tg`), so the value has to be inferred from the three
/// things it does say — the mode, the equipment, and how hard the sets were rated.
///
/// Treat every number below as ±30%. That is not a defect to be engineered away, it is what
/// energy expenditure estimation is: a chamber study would do better and a wristwatch would
/// not. The app's job is to be honest about it, which is why `evolution()` in nutrition.dart
/// reports the gap against the scale rather than presenting these as measurements.

/// Compendium 02050 — resistance training, multiple exercises, 8-15 reps, moderate effort.
const metStrengthEasy = 3.5;

/// Compendium 02054 — resistance training, vigorous effort. What a session taken near failure
/// throughout is worth.
const metStrengthHard = 6.0;

/// Sessions where nothing was rated land here.
///
/// The effort scale is opt-in (`AppState.effort` is null until chosen), so most logs carry no
/// RIR at all. Assuming those were all easy would quietly under-count every unrated session;
/// assuming they were all hard would flatter it. This sits between the two Compendium entries
/// because most training genuinely is neither.
const metStrengthDefault = 4.5;

/// A held position — planks, hangs, wall sits. Compendium 02052, calisthenics light effort.
const metTimeHold = 3.8;

/// Cardio with nothing said about how fast. Compendium's general "exercise, unspecified".
const metCardioDefault = 7.0;

/// Equipment that says more about the effort than the body part does.
///
/// Only the machines whose steady-state cost genuinely differs are listed; anything absent
/// falls back to [metCardioDefault], which is the honest answer for "some cardio machine".
const _byEquipment = <String, double>{
  'stationary bike': 7.0, // 01015, moderate 100 W
  'elliptical machine': 5.0, // 02048
  'skierg machine': 7.0, // 02080, ski ergometer general
  'stepmill machine': 9.0, // 02065, stair-treadmill general
  'upper body ergometer': 4.5, // 02068, arm ergometer
  'rope': 11.0, // 15551, rope jumping moderate
  'sled machine': 8.0, // 02040, pushing/pulling heavy load
  'tire': 8.0,
};

/// MET from speed, for cardio sets that logged one.
///
/// Two straight lines fitted to the Compendium's walking and running entries. They cross near
/// 7 km/h, which is about where people stop walking and start running, and where the energy
/// cost per distance stops being flat. Below that the fit is walking (01110 at 4.8 km/h = 3.5,
/// 01130 at 6.4 km/h = 5.0); above it running (12030 at 8 km/h = 8.3, 12050 at 12 km/h = 11.8,
/// 12070 at 14 km/h = 13.5).
double metForSpeed(double kmh) {
  if (kmh <= 0) return metCardioDefault;
  final met = kmh < 7 ? 0.8 * kmh - 0.2 : 0.87 * kmh + 1.3;
  // A treadmill that says 45 km/h is a mis-entry, not an Olympic final.
  return met.clamp(2.0, 20.0);
}

/// The MET a *planned* exercise is worth, before it has been done.
///
/// No sets have been logged, so there is no effort to read and strength work falls to
/// [metStrengthDefault]. Cardio still has its prescription, which is usually the part of a plan
/// that carries a speed.
double metOfConfig(ExerciseConfig cfg) => switch (modeOf(cfg)) {
      'cardio' => _cardioMet(cfg, cfg.speed),
      'time' => metTimeHold,
      _ => metStrengthDefault,
    };

/// The MET one logged exercise was worth, using what its sets actually recorded.
double metOfEntry(WorkoutEntry e) {
  final cfg = e.cfg;
  final done = [for (final s in e.sets) if (s.done) s];
  switch (modeOf(cfg)) {
    case 'cardio':
      // Average the speeds actually held, not the one that was prescribed.
      final speeds = [for (final s in done) if ((s.speed ?? 0) > 0) s.speed!];
      final speed = speeds.isEmpty
          ? null
          : speeds.reduce((a, b) => a + b) / speeds.length;
      return _cardioMet(cfg, speed);
    case 'time':
      return metTimeHold;
    default:
      return _strengthMet(done);
  }
}

double _cardioMet(ExerciseConfig cfg, double? speed) {
  if (speed != null && speed > 0) return metForSpeed(speed);
  final eq = exdb[cfg.id]?.eq;
  return _byEquipment[eq] ?? metCardioDefault;
}

/// Strength work, scaled by how much of it was taken close to failure.
///
/// Reuses [isHardSet] rather than re-deriving the threshold, so "hard" means the same thing
/// here as it does on the muscle map's hard-sets view — one definition, one place to change it.
double _strengthMet(List<SetLog> done) {
  final rated = [for (final s in done) if (rirOf(s) != null) s];
  if (rated.isEmpty) return metStrengthDefault;
  final hard = rated.where(isHardSet).length / rated.length;
  return metStrengthEasy + (metStrengthHard - metStrengthEasy) * hard;
}

/// The MET for a whole finished session, weighted by how much work each exercise carried.
///
/// Weighted by completed sets, not by exercise count: three sets of squats say more about what
/// the hour cost than one set of curls does. An empty session reports the strength default
/// rather than zero, so a logged-but-unticked workout does not read as free.
double metOfWorkout(Workout w) {
  var num = 0.0;
  var den = 0.0;
  for (final e in w.entries) {
    final sets = e.sets.where((s) => s.done).length;
    if (sets == 0) continue;
    num += metOfEntry(e) * sets;
    den += sets;
  }
  return den == 0 ? metStrengthDefault : num / den;
}

/// The MET a routine would be worth if it were done as written.
double metOfRoutine(Routine? r) {
  var num = 0.0;
  var den = 0.0;
  for (final cfg in r?.ex ?? const <ExerciseConfig>[]) {
    final sets = math.max(1, (cfg.sets ?? 1).round());
    num += metOfConfig(cfg) * sets;
    den += sets;
  }
  return den == 0 ? metStrengthDefault : num / den;
}
