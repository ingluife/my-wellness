import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/history.dart';
import 'package:my_wellness/domain/nutrition.dart';
import 'package:my_wellness/ui/sheets/workout_flow.dart';

import 'helpers.dart';

/// A day is what somebody trained, not what they trained last.
///
/// Home used to reduce the day to its latest-ending session — `todayWorkouts.reduce(...)` — so a
/// second session logged the same day vanished from the card with nothing to say it was missing.
/// These tests pin the arithmetic that replaced it, and above all the invariant that a day
/// holding one workout still reads exactly as that workout did.
void main() {
  setUpAll(loadExercises);

  const bench = 'e0001';
  const squat = 'e0002';

  /// A finished session: [min] minutes on the clock, [sets] completed sets of [kg]x[reps].
  Workout session(
    String id, {
    String d = '2026-09-03',
    int min = 60,
    int sets = 4,
    double kg = 100,
    double reps = 10,
    String exercise = bench,
    double? bw,
    List<String> prs = const [],
  }) {
    final start = DateTime(2026, 9, 3, 8).millisecondsSinceEpoch;
    return Workout(
      id: id,
      d: d,
      start: start,
      end: start + min * 60000,
      name: id,
      bw: bw,
      // Stamped at finish in the real flow, so tests carry it the same way.
      vol: kg * reps * sets,
      prs: [...prs],
      entries: [
        WorkoutEntry(
          id: exercise,
          target: ExerciseConfig(id: exercise),
          sets: [for (var i = 0; i < sets; i++) SetLog(w: kg, r: reps, done: true)],
        ),
      ],
    );
  }

  /// The tiles keyed by label, so an assertion names what it is reading.
  Map<String, String> tiles(List<Workout> ws, AppState s) =>
      {for (final t in dayStatTiles(ws, s)) t.label: t.value};

  AppState stateWith(List<Workout> ws, {double? weighIn}) {
    final s = AppState.defaults();
    s.workouts.addAll(ws);
    if (weighIn != null) {
      s.bodyweight.add(BodyWeightEntry(d: '2026-09-03', w: weighIn));
    }
    return s;
  }

  group('workoutsOn', () {
    test('returns every session that day, in the order they were logged', () {
      final a = session('a');
      final b = session('b');
      final other = session('c', d: '2026-09-02');
      final s = stateWith([other, a, b]);

      expect(workoutsOn(s, '2026-09-03').map((w) => w.id), ['a', 'b']);
      expect(workoutsOn(s, '2026-09-02').map((w) => w.id), ['c']);
      expect(workoutsOn(s, '2026-09-01'), isEmpty);
    });
  });

  group('workoutMs', () {
    test('is the time on the clock', () {
      expect(workoutMs(session('a', min: 45)), 45 * 60000);
    });

    test('an imported session with no end contributes nothing, never a negative', () {
      // Imported history has a start and no finish. Subtracting raw would hand a day's total a
      // large negative number and report less work than was actually done.
      final imported = session('a')..end = 0;
      expect(workoutMs(imported), 0);
    });
  });

  group('one workout reads exactly as it always did', () {
    test('the single-session tiles are that session, not an aggregate of something else', () {
      final w = session('a', min: 50, sets: 4, kg: 100, reps: 10);
      final s = stateWith([w]);
      final t = tiles([w], s);

      expect(t['Duration'], '50 min');
      expect(t['Volume'], '4,000');
      expect(t['Sets'], '4');
    });

    test('workoutStatTiles and dayStatTiles of one workout cannot disagree', () {
      // They are one implementation now; this is the test that keeps them that way.
      final w = session('a', bw: 80);
      final s = stateWith([w]);
      expect(workoutStatTiles(w, s), dayStatTiles([w], s));
    });
  });

  group('a day with two sessions', () {
    test('duration, volume and sets are the day\'s totals', () {
      final morning = session('a', min: 45, sets: 4, kg: 100, reps: 10);
      final evening = session('b', min: 30, sets: 3, kg: 50, reps: 10, exercise: squat);
      final s = stateWith([morning, evening]);
      final t = tiles([morning, evening], s);

      expect(t['Duration'], '1h 15m', reason: '45 + 30, not the later session alone');
      expect(t['Volume'], '5,500', reason: '4,000 + 1,500');
      expect(t['Sets'], '7', reason: '4 + 3');
    });

    test('the gap between a morning and an evening session is not training time', () {
      // Wall-clock from the first start to the last end would count the hours in between.
      final morning = session('a', min: 45);
      final evening = session('b', min: 30);
      evening.start = DateTime(2026, 9, 3, 19).millisecondsSinceEpoch;
      evening.end = evening.start + 30 * 60000;
      final s = stateWith([morning, evening]);

      expect(tiles([morning, evening], s)['Duration'], '1h 15m');
    });

    test('each session is costed at its own weigh-in', () {
      final heavy = session('a', bw: 100);
      final light = session('b', bw: 60);
      final s = stateWith([heavy, light]);

      final apart = workoutBurn(heavy, 100) + workoutBurn(light, 60);
      expect(tiles([heavy, light], s)['Burned'], '${apart.round()}');
    });

    test('with no body weight anywhere, the fourth tile is PRs instead', () {
      final a = session('a', prs: [bench]);
      final s = stateWith([a]);
      expect(tiles([a], s).containsKey('Burned'), isFalse);
      expect(tiles([a], s)['PRs'], '1');
    });

    test('the same lift PR\'d in both sessions is one PR, not two', () {
      // A union, not a sum: the second PR supersedes the first, it does not stand beside it.
      final morning = session('a', prs: [bench]);
      final evening = session('b', prs: [bench]);
      final s = stateWith([morning, evening]);

      expect(tiles([morning, evening], s)['PRs'], '1');
    });

    test('different lifts PR\'d in each session both count', () {
      final morning = session('a', prs: [bench]);
      final evening = session('b', prs: [squat]);
      final s = stateWith([morning, evening]);

      expect(tiles([morning, evening], s)['PRs'], '2');
    });

    test('an imported session drags nothing off the day\'s duration', () {
      final logged = session('a', min: 45);
      final imported = session('b', min: 30)..end = 0;
      final s = stateWith([logged, imported]);

      // Its sets and volume still count; only its unknown clock is left out.
      final t = tiles([logged, imported], s);
      expect(t['Duration'], '45 min');
      expect(t['Sets'], '8');
    });
  });
}
