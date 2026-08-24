import 'dart:math' as math;

import '../data/models/app_state.dart';
import 'exercises.dart';

/// Which muscles an exercise trains, and how hard — the data behind every muscle map.
/// Ported from lib/muscles.js.
///
/// The exercise dataset names muscles in free text and is not consistent about it:
/// "shoulders", "deltoids" and "delts" are the same thing, so are "quads" and "quadriceps",
/// "lats" and "latissimus dorsi", "core" and "abdominals". Nineteen primary and forty secondary
/// spellings collapse onto the eighteen muscles the body map can actually draw, via [_alias].
/// Anything genuinely undrawable (hands, ankles, "cardiovascular system") maps to null and is
/// dropped rather than guessed at.

/// The muscles a map can shade, in head-to-toe order — also the order of any list built from
/// them, so "what am I neglecting" reads top-down like a body.
const muscles = <String>[
  'trapezius', 'deltoids', 'chest', 'upper-back', 'serratus',
  'biceps', 'triceps', 'forearm',
  'abs', 'obliques', 'lower-back',
  'gluteal', 'quadriceps', 'hamstring', 'adductors', 'hip-flexors',
  'calves', 'tibialis',
];

/// Drawn as the silhouette, never shaded: they carry no training load.
const inert = <String>['head', 'hair', 'neck', 'hands', 'feet', 'knees', 'ankles'];

/// English display names; these strings are the i18n keys.
const muscleName = <String, String>{
  'trapezius': 'Traps', 'deltoids': 'Shoulders', 'chest': 'Chest', 'upper-back': 'Upper back',
  'serratus': 'Serratus', 'biceps': 'Biceps', 'triceps': 'Triceps', 'forearm': 'Forearms',
  'abs': 'Abs', 'obliques': 'Obliques', 'lower-back': 'Lower back', 'gluteal': 'Glutes',
  'quadriceps': 'Quads', 'hamstring': 'Hamstrings', 'adductors': 'Adductors',
  'hip-flexors': 'Hip flexors', 'calves': 'Calves', 'tibialis': 'Shins',
};

/// Every spelling that occurs in the dataset's `tg` and `sm` fields. null = not drawable.
const _alias = <String, String?>{
  // primaries
  'abs': 'abs', 'pectorals': 'chest', 'biceps': 'biceps', 'glutes': 'gluteal',
  'delts': 'deltoids', 'triceps': 'triceps', 'upper back': 'upper-back', 'lats': 'upper-back',
  'calves': 'calves', 'quads': 'quadriceps', 'forearms': 'forearm', 'hamstrings': 'hamstring',
  'spine': 'lower-back', 'traps': 'trapezius', 'adductors': 'adductors',
  'serratus anterior': 'serratus', 'abductors': 'gluteal', 'levator scapulae': 'trapezius',
  'cardiovascular system': null,
  // secondaries
  'shoulders': 'deltoids', 'deltoids': 'deltoids', 'rear deltoids': 'deltoids',
  'rotator cuff': 'deltoids', 'quadriceps': 'quadriceps', 'core': 'abs', 'abdominals': 'abs',
  'lower abs': 'abs', 'chest': 'chest', 'upper chest': 'chest', 'hip flexors': 'hip-flexors',
  'obliques': 'obliques', 'lower back': 'lower-back', 'rhomboids': 'upper-back',
  'trapezius': 'trapezius', 'back': 'upper-back', 'latissimus dorsi': 'upper-back',
  'brachialis': 'biceps', 'soleus': 'calves', 'shins': 'tibialis', 'wrists': 'forearm',
  'wrist flexors': 'forearm', 'wrist extensors': 'forearm', 'grip muscles': 'forearm',
  'groin': 'adductors', 'inner thighs': 'adductors',
  'ankles': null, 'feet': null, 'hands': null, 'ankle stabilizers': null,
  'sternocleidomastoid': null,
};

/// Custom exercises carry only a body part, so they fall back to it. Weights inside a group sum
/// to 1 — "upper legs" spreads over three muscles rather than counting triple.
const _byBodyPart = <String, Map<String, double>>{
  'chest': {'chest': 1},
  'back': {'upper-back': 0.75, 'lower-back': 0.25},
  'shoulders': {'deltoids': 1},
  'upper arms': {'biceps': 0.5, 'triceps': 0.5},
  'lower arms': {'forearm': 1},
  'waist': {'abs': 0.7, 'obliques': 0.3},
  'upper legs': {'quadriceps': 0.4, 'hamstring': 0.35, 'gluteal': 0.25},
  'lower legs': {'calves': 0.8, 'tibialis': 0.2},
  'neck': {'trapezius': 1},
  'cardio': {},
};

/// A supporting muscle counts this much against a primary.
const _secondary = 0.4;

/// Muscles one exercise trains: `{ slug: 0..1 }`.
Map<String, double> musclesOf(Exercise? ex) {
  if (ex == null) return {};
  final out = <String, double>{};
  void add(String? name, double w) {
    final slug = _alias[(name ?? '').toLowerCase().trim()];
    if (slug != null) out[slug] = math.max(out[slug] ?? 0, w);
  }

  add(ex.tg, 1);
  for (final m in ex.sm) {
    add(m, _secondary);
  }
  // Nothing recognised (custom exercises, or a target we do not draw) — use the body part.
  if (out.isEmpty) out.addAll(_byBodyPart[ex.bp] ?? const {});
  return out;
}

/// Training load per muscle, in "effective sets".
///
/// [items] is (id, sets) — sets being a count, so a 4x8 bench press weighs four times a single
/// set. Volume in kg is deliberately not used: 100 kg of leg press against 12 kg of lateral
/// raise says nothing about which muscle worked harder.
Map<String, double> loadOf(Iterable<({String id, int sets})> items) {
  final load = <String, double>{};
  for (final it in items) {
    if (it.sets == 0) continue;
    final m = musclesOf(exdb[it.id]);
    m.forEach((slug, v) => load[slug] = (load[slug] ?? 0) + v * it.sets);
  }
  return load;
}

/// Load for finished workouts (only sets actually ticked off count).
///
/// [pick] narrows that further — the map can then answer "where did the *hard* sets go", which
/// is a different question from where the sets went: a muscle can lead on volume and still
/// never be trained near failure.
Map<String, double> loadOfWorkouts(Iterable<Workout> workouts, [bool Function(SetLog)? pick]) =>
    loadOf([
      for (final w in workouts)
        for (final e in w.entries)
          (id: e.id, sets: e.sets.where((s) => s.done && (pick == null || pick(s))).length)
    ]);

/// Load a routine *would* produce, from its planned set counts.
Map<String, double> loadOfRoutine(Routine? routine) => loadOf([
      for (final c in routine?.ex ?? const <ExerciseConfig>[])
        (id: c.id ?? '', sets: (c.sets ?? 1).round())
    ]);

/// Load for a workout still in progress — the sets ticked so far.
Map<String, double> loadOfActive(ActiveWorkout? active) => loadOf([
      for (final e in active?.entries ?? const <WorkoutEntry>[])
        (id: e.id, sets: e.sets.where((s) => s.done).length)
    ]);

/// Shade buckets 0-4 per muscle, relative to the hardest-worked muscle in the same window.
///
/// Relative rather than absolute on purpose: the map answers "is my training balanced", which
/// only means anything as a comparison within one period.
Map<String, int> levelsOf(Map<String, double> load) {
  final max = muscles.fold(0.0, (a, m) => math.max(a, load[m] ?? 0));
  return {
    for (final m in muscles)
      m: (load[m] ?? 0) == 0 || max <= 0
          ? 0
          : math.max(1, math.min(4, ((load[m]! / max) * 4).ceil()))
  };
}

/// Muscles sorted hardest-worked first; untrained ones last, in body order.
({List<String> worked, List<String> missed}) rankOf(Map<String, double> load) {
  final worked = [for (final m in muscles) if ((load[m] ?? 0) > 0) m]
    ..sort((a, b) => load[b]!.compareTo(load[a]!));
  final missed = [for (final m in muscles) if (!((load[m] ?? 0) > 0)) m];
  return (worked: worked, missed: missed);
}
