import 'dart:math' as math;

import '../data/models/app_state.dart';
import 'exercises.dart';
import 'format.dart';
import 'i18n.dart';

/// Pure helpers over the state object, ported 1:1 from lib/history.js.

/// How an exercise is logged.
///
/// This used to be derived from the body part alone, which meant a plank or a farmer's carry
/// could only be timed by filing it under cardio. A routine entry can now say so explicitly:
///
///   reps   — weight x reps      sets look like `{ w, r }`
///   time   — a work duration    sets look like `{ sec, w }`  (w = 0 for bodyweight)
///   cardio — duration + speed   sets look like `{ min, speed }`
///
/// An entry without `mode` behaves exactly as before, so every existing plan, workout and
/// plan file is read unchanged and nothing needs migrating.
String modeOf(ExerciseConfig? cfg) {
  final m = cfg?.mode;
  if (m == 'reps' || m == 'time' || m == 'cardio') return m!;
  return exdb.isCardio(cfg?.id) ? 'cardio' : 'reps';
}

bool isTimed(ExerciseConfig? cfg) => modeOf(cfg) == 'time';

/// The exercise carries no load of its own, so `w` means *added* weight and is asked for only
/// once you say there is some. Seeded from the equipment field. Spelled out rather than `bw`,
/// which a workout already uses for the weigh-in it was logged at — two different things one
/// letter apart is a bug waiting.
bool isBw(ExerciseConfig? cfg) =>
    cfg?.bodyweight ?? exdb.isBodyweightEq(cfg?.id);

/// The exercise is unilateral. You still log what you did: 16, the total across both sides.
/// The split is derived for planning ("8 per side"), never entered — a number that sometimes
/// means one side and sometimes both is the thing that made this ambiguous in the first place.
bool isPerSide(ExerciseConfig? cfg) => cfg?.side ?? false;

/// What one side did, for display only. Half of an odd total is shown as it falls (8.5)
/// rather than rounded away: it means the sides were not even, which is worth seeing.
double sideReps(double? reps) => (reps ?? 0) / 2;

/// Unilateral work moves in pairs, so its rep target steps by two — 16, 18, 20 — and a total
/// that stayed odd would put a rep on one side and not the other.
double repStep(ExerciseConfig? cfg) => isPerSide(cfg) ? 2 : 1;

/// mm:ss for a work duration — seconds alone read badly past a minute ("90 s" vs "1:30").
String fmtSec(num? sec) {
  final n = math.max(0, (sec ?? 0).round());
  return '${n ~/ 60}:${(n % 60).toString().padLeft(2, '0')}';
}

/// A scale for how hard a set felt.
typedef EffortScale = ({String f, String hd, double step, double min, double max});

/// Two scales for the same thing, kept in their own fields: RIR counts the reps still in the
/// tank, RPE reads the same effort off a 10-point scale from the top (RPE 8 ≈ RIR 2). A set
/// logged on one scale is never silently rewritten as the other — switching the setting
/// changes what new sets ask for, nothing else.
///
/// `min`..`max` is the range the stepper walks. RIR bottoms out at 0 (a set taken to failure);
/// RPE bottoms out at 6, since the scale is only meaningful for working sets and anything
/// lighter is a warm-up nobody rates.
const effortScales = <String, EffortScale>{
  'rir': (f: 'rir', hd: 'RIR', step: 0.5, min: 0, max: 10),
  'rpe': (f: 'rpe', hd: 'RPE', step: 0.5, min: 6, max: 10),
};

/// One tap of an effort stepper.
///
/// Empty is not 0 — an unlogged effort must not become "went to failure" from one stray tap —
/// so − on an empty cell leaves it empty, and + starts at the bottom of the scale and walks up
/// from there in even steps. Stepping back off the bottom clears the cell again, so a mistap
/// is undoable. null means "nothing logged"; the caller stores that by dropping the key.
double? stepEffort(String kind, double? cur, int dir) {
  final e = effortScales[kind];
  if (e == null) return cur;
  if (cur == null) return dir < 0 ? null : e.min;
  final n = ((cur + dir * e.step) * 100).round() / 100;
  if (dir < 0 && n < e.min) return null;
  // Only the ceiling is enforced on the way up: a value typed below the floor (nothing stops
  // someone entering RPE 3) still steps in even increments instead of snapping to the floor.
  return dir > 0 ? math.min(e.max, n) : math.max(e.min, n);
}

/// A typed effort is capped but not floored — clamping up while someone types "10" would turn
/// the first keystroke into the floor and fight the input.
double? capEffort(String kind, double? v) {
  final e = effortScales[kind];
  return v == null || e == null ? v : math.min(e.max, v);
}

/// Which scale a profile logs.
///
/// `showRir` is the boolean this replaced and is only consulted when the profile has no answer
/// of its own — an explicit 'none' has to win over it, or a backup or another device that
/// still carries the old flag would switch the column back on.
String effortOf(AppState? s) {
  final e = s?.effort;
  if (e == 'none' || effortScales.containsKey(e)) return e!;
  return (s?.showRir ?? false) ? 'rir' : 'none';
}

/// The "(RIR 2)" / "(RPE 8)" tail on a set summary, empty when nothing was logged.
String _effortTail(SetLog s) {
  final k = s.rir != null ? 'rir' : (s.rpe != null ? 'rpe' : null);
  return k == null ? '' : ' (${effortScales[k]!.hd} ${fmtNum(s.field(k))})';
}

/// One-line summary of a logged set. [cfg] carries the mode when the caller has it (a routine
/// entry or a workout entry); passing an id alone keeps the old body-part behaviour.
String setLabel(String id, SetLog s, [ExerciseConfig? cfg]) {
  final c = (cfg ?? ExerciseConfig()).withId(cfg?.id ?? id);
  final mode = modeOf(c);
  if (mode == 'cardio') return '${(s.min ?? 0).round()} min @ ${fmtNum(s.speed ?? 0)} km/h';
  if (mode == 'time') {
    return fmtSec(s.sec) + ((s.w ?? 0) > 0 ? ' · ${fmtNum(s.w)}' : '');
  }
  // Bodyweight reads as what you did — "12", or "+10 × 12" once there is a belt involved —
  // rather than "0×12", which says a set was performed with no weight and means nothing.
  // A per-side set needs no mark here: the number logged is the total, like every other set.
  final reps = fmtNum(s.r ?? 0);
  if (isBw(c)) {
    final load = (s.w ?? 0) > 0 ? '+${fmtNum(s.w)} × ' : '';
    return '$load$reps${_effortTail(s)}';
  }
  return '${fmtNum(s.w ?? 0)}×$reps${_effortTail(s)}';
}

/// Default config for a freshly added exercise.
ExerciseConfig defaultConfig(String id, [String? mode]) {
  final m = mode ?? modeOf(ExerciseConfig(id: id));
  if (m == 'cardio') return ExerciseConfig(id: id, sets: 1, min: 20, speed: 8);
  // The flag is written only when it is true, so a barbell config is byte-for-byte what it was
  // before the flag existed and a plan file gains nothing it does not need.
  final bw = exdb.isBodyweightEq(id) ? true : null;
  if (m == 'time') {
    return ExerciseConfig(id: id, sets: 3, sec: 45, weight: 0, mode: 'time', bodyweight: bw);
  }
  return ExerciseConfig(id: id, sets: 3, reps: 10, weight: 0, mode: 'reps', bodyweight: bw);
}

/// One-line summary of a planned exercise ("3 × 10 · 60 kg"), shared by the routine editor and
/// the plan export so a mode is described the same way everywhere.
String exLine(ExerciseConfig cfg, String unit) {
  final mode = modeOf(cfg);
  final n = fmtNum(cfg.sets ?? 1);
  // Added weight reads as added: "+10 kg" on a dip belt, "60 kg" on a barbell.
  final w = cfg.weight ?? 0;
  final load = w != 0 ? ' · ${isBw(cfg) ? '+' : ''}${fmtNum(w)} $unit' : '';
  if (mode == 'cardio') {
    return '$n × ${(cfg.min ?? 20).round()} min @ ${fmtNum(cfg.speed ?? 8)} km/h';
  }
  if (mode == 'time') return '$n × ${fmtSec(cfg.sec ?? 45)}$load';
  // This is the line with room for it, so the split is spelled out: "3 × 16 · 8/side".
  final split = isPerSide(cfg) ? ' · ${t('{0}/side', fmtNum(sideReps(cfg.reps)))}' : '';
  return '$n × ${fmtNum(cfg.reps)}$load$split';
}

/// Drop superset ids that no longer have an adjacent partner (after unlink/reorder/remove).
void cleanupSg(List<ExerciseConfig> ex) {
  for (var i = 0; i < ex.length; i++) {
    final sg = ex[i].sg;
    if (sg == null) continue;
    final prev = i > 0 ? ex[i - 1].sg : null;
    final next = i + 1 < ex.length ? ex[i + 1].sg : null;
    if (prev != sg && next != sg) ex[i].sg = null;
  }
}

/// The last session this exercise was actually trained in.
typedef LastEntry = ({String d, List<SetLog> sets, ExerciseConfig? target});

LastEntry? lastEntryFor(AppState s, String exId) {
  for (var i = s.workouts.length - 1; i >= 0; i--) {
    final w = s.workouts[i];
    WorkoutEntry? en;
    for (final e in w.entries) {
      if (e.id == exId) {
        en = e;
        break;
      }
    }
    // `target` is what the session prescribed; finished workouts carry it so labels and the
    // progression engine can read a session back the way it was logged. Older workouts have
    // none — modeOf() falls back to the body part for them, which is what they were.
    if (en != null && en.sets.any((x) => x.done)) {
      return (d: w.d, sets: [for (final x in en.sets) if (x.done) x], target: en.target);
    }
  }
  return null;
}

double bestWeightFor(AppState s, String exId) {
  var best = 0.0;
  for (final w in s.workouts) {
    for (final e in w.entries) {
      if (e.id != exId) continue;
      for (final x in e.sets) {
        if (x.done && (x.w ?? 0) > best) best = x.w!;
      }
      if ((e.topW ?? 0) > best) best = e.topW!;
    }
  }
  return best;
}

/// The routine that applies on a given day: the per-date override if there is one, otherwise
/// the weekly plan. 'rest' is an override meaning "nothing today".
String? effectiveRoutineId(AppState s, String iso) {
  final ov = s.dayPlan[iso];
  if (ov == 'rest') return null;
  if (ov != null && s.routines.any((r) => r.id == ov)) return ov;
  return s.week['${jsDay(dayOf(iso))}'];
}

Routine? effectiveRoutine(AppState s, String iso) {
  final id = effectiveRoutineId(s, iso);
  if (id == null) return null;
  for (final r in s.routines) {
    if (r.id == id) return r;
  }
  return null;
}

/// Build the sets a session opens with: last time's numbers where there are any, the plan's
/// where there are not.
List<SetLog> buildSets(AppState s, ExerciseConfig cfg) {
  final last = lastEntryFor(s, cfg.id ?? '');
  final n = math.max(1, (cfg.sets ?? 1).round());
  final mode = modeOf(cfg);
  final sets = <SetLog>[];

  // Last time's set at the same position, falling back to its final set when the plan grew.
  SetLog? prevAt(int i) => last == null
      ? null
      : (i < last.sets.length ? last.sets[i] : last.sets[last.sets.length - 1]);

  if (mode == 'cardio') {
    for (var i = 0; i < n; i++) {
      final prev = prevAt(i);
      sets.add(SetLog(
        min: prev?.min ?? cfg.min ?? 20,
        speed: prev?.speed ?? cfg.speed ?? 8,
      ));
    }
    return sets;
  }
  if (mode == 'time') {
    for (var i = 0; i < n; i++) {
      // Only carry a previous value over when it came from a timed set — switching an
      // exercise from reps to time must not seed the duration from a rep count.
      final prev = prevAt(i);
      final carried = prev != null && (prev.sec ?? 0) > 0 ? prev : null;
      sets.add(SetLog(
        sec: carried?.sec ?? cfg.sec ?? 45,
        w: carried != null ? (carried.w ?? 0) : (cfg.weight ?? 0),
      ));
    }
    return sets;
  }
  final conf = s.exWeights[cfg.id];
  for (var i = 0; i < n; i++) {
    final prev = prevAt(i);
    final usable = prev != null && (prev.r ?? 0) > 0 ? prev : null;
    sets.add(SetLog(
      w: conf != null && conf.w > 0 ? conf.w : (usable?.w ?? cfg.weight),
      r: usable?.r ?? cfg.reps,
    ));
  }
  return sets;
}

/// No special case for unilateral work: a per-side set logs its total, so both sides are
/// already in the rep count that arrives here.
double workoutVolume(Workout w) {
  var v = 0.0;
  for (final e in w.entries) {
    for (final s in e.sets) {
      if (s.done) v += (s.w ?? 0) * (s.r ?? 0);
    }
  }
  return v;
}

int setsDone(Workout w) {
  var n = 0;
  for (final e in w.entries) {
    for (final s in e.sets) {
      if (s.done) n++;
    }
  }
  return n;
}

/// Every session logged on [iso], in the order they were logged.
///
/// Nothing stops a day holding several — `_doFinishWorkout` appends unconditionally, so a
/// freestyle session logged on top of the planned one is two workouts sharing a date. Every
/// screen that asks "what happened on this day" has to be prepared for a list, and each one used
/// to open-code this scan; the day is a real unit and deserves one reading of it.
List<Workout> workoutsOn(AppState s, String iso) =>
    [for (final w in s.workouts) if (w.d == iso) w];

/// How long one session took, in ms.
///
/// Guards the two ways the clock can be missing, neither of which is hypothetical: an imported
/// session has no `end` at all, and a subtraction on a corrupt pair must not come back negative
/// and drag a day's total below what was actually trained. `durPart` already suppresses anything
/// under a minute, so a zero here renders as nothing rather than as "0m".
int workoutMs(Workout w) => ((w.end == 0 ? w.start : w.end) - w.start).clamp(0, 1 << 40);

int setsDoneActive(ActiveWorkout? a) {
  var n = 0;
  for (final e in a?.entries ?? const <WorkoutEntry>[]) {
    for (final s in e.sets) {
      if (s.done) n++;
    }
  }
  return n;
}

BodyWeightEntry? lastBW(AppState s) =>
    s.bodyweight.isEmpty ? null : s.bodyweight.last;

/// Group consecutive items sharing a superset id into "units" of indices.
///
/// Items may be routine exercises or active-workout entries — both carry `sg`. A unit is done
/// back-to-back with a rest only after the last exercise in it, and Prev/Next moves by unit.
List<List<int>> supersetUnits(List<HasSuperset> items) {
  final units = <List<int>>[];
  for (var i = 0; i < items.length; i++) {
    final sg = items[i].sg;
    final prev = i > 0 ? items[i - 1].sg : null;
    if (i > 0 && sg != null && prev != null && sg == prev) {
      units.last.add(i);
    } else {
      units.add([i]);
    }
  }
  return units;
}

List<int> unitOf(List<List<int>> units, int idx) =>
    units.firstWhere((u) => u.contains(idx), orElse: () => [idx]);

/// Consecutive calendar weeks with at least one workout, counting back from this week.
///
/// This week not having one yet does not break the streak — that is what the `i > 0` guard is
/// for; on Monday morning you have not lost anything.
int streakWeeks(AppState s) {
  if (s.workouts.isEmpty) return 0;
  final weeks = {for (final w in s.workouts) weekKey(w.d)};
  var streak = 0;
  var cur = DateTime.now();
  for (var i = 0; i < 520; i++) {
    if (weeks.contains(weekKey(isoOf(cur)))) {
      streak++;
    } else if (i > 0) {
      break;
    }
    cur = DateTime(cur.year, cur.month, cur.day - 7, 12);
  }
  return streak;
}
