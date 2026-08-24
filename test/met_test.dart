import 'package:flutter_test/flutter_test.dart';
import 'package:my_open_gym/data/models/app_state.dart';
import 'package:my_open_gym/domain/met.dart';

import 'helpers.dart';

/// The MET table is the shakiest input in the whole nutrition feature — it is inferred from a
/// dataset that carries no intensity at all. These tests do not claim the numbers are right;
/// they pin the shape of the inference so it cannot drift silently: harder sets cost more,
/// faster running costs more, and a machine the table knows beats the generic fallback.
void main() {
  setUpAll(loadExercises);

  WorkoutEntry entry(String id, List<SetLog> sets, {String? mode}) => WorkoutEntry(
        id: id,
        target: ExerciseConfig(id: id, mode: mode),
        sets: sets,
      );

  group('speed', () {
    test('tracks the Compendium within a rounding error', () {
      // 01110 walking 4.8 km/h = 3.5 · 01130 at 6.4 = 5.0
      expect(metForSpeed(4.8), closeTo(3.5, 0.2));
      expect(metForSpeed(6.4), closeTo(5.0, 0.2));
      // 12030 running 8 km/h = 8.3 · 12050 at 12 = 11.8 · 12070 at 14 = 13.5
      expect(metForSpeed(8), closeTo(8.3, 0.2));
      expect(metForSpeed(12), closeTo(11.8, 0.2));
      expect(metForSpeed(14), closeTo(13.5, 0.2));
    });

    test('never falls as speed rises, and climbs once clear of the floor', () {
      var prev = 0.0;
      for (var kmh = 1.0; kmh <= 20; kmh += 0.5) {
        final met = metForSpeed(kmh);
        expect(met, greaterThanOrEqualTo(prev), reason: 'at $kmh km/h');
        // A stroll is held at the floor rather than fitted, because the walking line runs
        // below any plausible cost of moving at all down there.
        if (kmh >= 3) expect(met, greaterThan(prev), reason: 'at $kmh km/h');
        prev = met;
      }
    });

    test('a stroll costs the floor rather than less than standing', () {
      expect(metForSpeed(1), 2.0);
      expect(metForSpeed(2), 2.0);
    });

    test('a mis-entered speed is clamped rather than believed', () {
      expect(metForSpeed(120), lessThanOrEqualTo(20));
      // Zero means "no speed logged", not "stood still" — the caller falls back to equipment.
      expect(metForSpeed(0), metCardioDefault);
    });
  });

  group('strength', () {
    test('an unrated session gets the middle value, not the easy one', () {
      final e = entry('0025', [SetLog(w: 60, r: 8, done: true)]);
      expect(metOfEntry(e), metStrengthDefault);
    });

    test('sets taken to failure cost more than sets left in reserve', () {
      final hard = entry('0025', [SetLog(w: 60, r: 8, done: true, rir: 0)]);
      final easy = entry('0025', [SetLog(w: 60, r: 8, done: true, rir: 5)]);
      expect(metOfEntry(hard), metStrengthHard);
      expect(metOfEntry(easy), metStrengthEasy);
      expect(metOfEntry(hard), greaterThan(metOfEntry(easy)));
    });

    test('a half-hard session lands between the two', () {
      final e = entry('0025', [
        SetLog(w: 60, r: 8, done: true, rir: 0),
        SetLog(w: 60, r: 8, done: true, rir: 5),
      ]);
      expect(metOfEntry(e), closeTo((metStrengthEasy + metStrengthHard) / 2, 1e-9));
    });

    test('unticked sets are not rated work', () {
      final e = entry('0025', [
        SetLog(w: 60, r: 8, done: true, rir: 5),
        SetLog(w: 60, r: 8, rir: 0), // never done
      ]);
      expect(metOfEntry(e), metStrengthEasy);
    });
  });

  group('cardio', () {
    test('a logged speed beats the equipment default', () {
      final e = entry('0025', [SetLog(min: 20, speed: 12, done: true)], mode: 'cardio');
      expect(metOfEntry(e), closeTo(metForSpeed(12), 1e-9));
    });

    test('with no speed it falls back to the generic value', () {
      final e = entry('0025', [SetLog(min: 20, done: true)], mode: 'cardio');
      expect(metOfEntry(e), metCardioDefault);
    });

    test('speeds are averaged over the sets that held one', () {
      final e = entry('0025', [
        SetLog(min: 10, speed: 8, done: true),
        SetLog(min: 10, speed: 12, done: true),
      ], mode: 'cardio');
      expect(metOfEntry(e), closeTo(metForSpeed(10), 1e-9));
    });
  });

  group('whole sessions', () {
    test('are weighted by sets, so the bulk of the work decides', () {
      final w = wk('2026-03-02', [
        entry('0025', [
          for (var i = 0; i < 9; i++) SetLog(w: 60, r: 8, done: true, rir: 0),
        ]),
        entry('0025', [SetLog(w: 20, r: 12, done: true, rir: 5)]),
      ]);
      // Nine hard sets against one easy one sits near the hard end, not halfway.
      expect(metOfWorkout(w), closeTo(metStrengthEasy + (metStrengthHard - metStrengthEasy) * 0.9, 1e-9));
    });

    test('a session with nothing ticked is not free', () {
      final w = wk('2026-03-02', [entry('0025', [SetLog(w: 60, r: 8)])]);
      expect(metOfWorkout(w), metStrengthDefault);
    });

    test('a routine can be costed before it is done', () {
      final r = Routine(id: 'r1', name: 'Push', ex: [
        ExerciseConfig(id: '0025', sets: 4, reps: 8),
      ]);
      expect(metOfRoutine(r), metStrengthDefault);
      expect(metOfRoutine(null), metStrengthDefault);
    });
  });
}
