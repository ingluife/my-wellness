import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/onerm.dart';


/// Ported from openGym/frontend/src/lib/onerm.test.js.
void main() {
  group('estimate1RM', () {
    test('returns the load unchanged for a single rep', () {
      expect(estimate1RM(100, 1), 100);
      expect(estimate1RM(62.5, 1), 62.5);
    });

    test('matches Epley by hand across the usual rep ranges', () {
      // 100 · (1 + 5/30)
      expect(estimate1RM(100, 5), 116.7);
      expect(estimate1RM(100, 10), 133.3);
      expect(estimate1RM(80, 8), 101.3);
      expect(estimate1RM(60, 3), 66);
    });

    test('rounds to one decimal', () {
      expect(estimate1RM(101.25, 7), 124.9);
      expect(estimate1RM(100, 3)! * 10, (estimate1RM(100, 3)! * 10).roundToDouble());
    });

    test('refuses reps beyond the cap rather than guessing', () {
      expect(estimate1RM(100, repCap), isNotNull);
      expect(estimate1RM(100, repCap + 1), isNull);
      expect(estimate1RM(60, 30), isNull);
    });

    test('rejects invalid, zero and negative input', () {
      expect(estimate1RM(0, 5), isNull);
      expect(estimate1RM(-100, 5), isNull);
      expect(estimate1RM(100, 0), isNull);
      expect(estimate1RM(100, -3), isNull);
      expect(estimate1RM(null, 5), isNull);
      expect(estimate1RM(100, null), isNull);
      expect(estimate1RM(double.nan, 5), isNull);
      expect(estimate1RM(double.infinity, 5), isNull);
    });

    test('offers the other documented formulas and agrees with them at low reps', () {
      expect(estimate1RM(100, 5, 'brzycki'), 112.5);
      expect(estimate1RM(100, 5, 'lombardi'), 117.5);
      expect(formulas.keys, contains('epley'));
    });

    test('keeps the formulas within a few percent up to 8 reps, and diverges most at the cap',
        () {
      double spread(int r) {
        final vs = [for (final f in formulas.keys) estimate1RM(100, r, f)!];
        return vs.reduce(math.max) - vs.reduce(math.min);
      }

      // One rep is measured, not estimated.
      expect(spread(1), 0);
      for (var r = 2; r <= 8; r++) {
        expect(spread(r), lessThan(6));
      }
      final upTo = [for (var r = 1; r < repCap; r++) spread(r)];
      // Why repCap exists.
      expect(spread(repCap), greaterThan(upTo.reduce(math.max)));
    });

    test('falls back to the default for an unknown formula name', () {
      expect(estimate1RM(100, 5, 'nope'), estimate1RM(100, 5));
    });
  });

  group('bestSetOf', () {
    test('picks the highest estimate, not the heaviest set', () {
      final entry = WorkoutEntry(id: 'x', sets: [
        SetLog(w: 100, r: 5, done: true), // 116.7
        SetLog(w: 110, r: 3, done: true), // 121.0
        SetLog(w: 120, r: 1, done: true), // 120.0
      ]);
      final best = bestSetOf(entry)!;
      expect(best.est, 121);
      expect(best.w, 110);
      expect(best.r, 3);
    });

    test('ignores sets that were never checked off', () {
      final entry = WorkoutEntry(id: 'x', sets: [
        SetLog(w: 100, r: 5, done: true),
        SetLog(w: 200, r: 5, done: false),
      ]);
      expect(bestSetOf(entry)!.w, 100);
    });

    test('ignores topW, which carries no rep count', () {
      final entry =
          WorkoutEntry(id: 'x', topW: 200, sets: [SetLog(w: 100, r: 5, done: true)]);
      expect(bestSetOf(entry)!.est, 116.7);
    });

    test('returns null for cardio and timed entries', () {
      expect(bestSetOf(WorkoutEntry(id: 'c', sets: [SetLog(min: 20, speed: 9, done: true)])),
          isNull);
      expect(bestSetOf(WorkoutEntry(id: 'p', sets: [SetLog(sec: 60, w: 0, done: true)])), isNull);
      expect(bestSetOf(WorkoutEntry(id: 'p', sets: [SetLog(sec: 60, w: 20, done: true)])), isNull);
    });

    test('survives a missing or empty entry', () {
      expect(bestSetOf(null), isNull);
      expect(bestSetOf(WorkoutEntry(id: 'x')), isNull);
    });
  });

  Workout at(String d, int start, String id, List<SetLog> sets) =>
      Workout(id: 'w$start', d: d, start: start, end: start, name: '', entries: [
        WorkoutEntry(id: id, sets: sets)
      ]);

  final s = AppState(workouts: [
    at('2026-01-01', 1, 'bench', [SetLog(w: 80, r: 5, done: true)]),
    at('2026-01-08', 2, 'squat', [SetLog(w: 100, r: 5, done: true)]),
    at('2026-01-15', 3, 'bench',
        [SetLog(w: 90, r: 5, done: true), SetLog(w: 90, r: 3, done: false)]),
    at('2026-01-22', 4, 'bench', [SetLog(w: 85, r: 5, done: true)]),
    at('2026-01-29', 5, 'run', [SetLog(min: 30, speed: 10, done: true)]),
  ]);

  group('e1rmSeries / best1RM', () {
    test('yields one chronological point per workout that produced an estimate', () {
      final pts = e1rmSeries(s, 'bench');
      expect(pts.map((p) => p.d), ['2026-01-01', '2026-01-15', '2026-01-22']);
      expect(pts.map((p) => p.y), [93.3, 105, 99.2]);
    });

    test('reports the all-time best with the set behind it', () {
      final b = best1RM(s, 'bench')!;
      expect(b.est, 105);
      expect(b.w, 90);
      expect(b.r, 5);
      expect(b.d, '2026-01-15');
      expect(b.t, 3);
    });

    test('has nothing to say about cardio or an unknown exercise', () {
      expect(e1rmSeries(s, 'run'), isEmpty);
      expect(best1RM(s, 'run'), isNull);
      expect(best1RM(s, 'nope'), isNull);
      expect(best1RM(AppState(), 'bench'), isNull);
    });
  });

  group('is1RMRecord', () {
    test('flags a session that beats every previous estimate', () {
      final rec = is1RMRecord(
          s, 'bench', WorkoutEntry(id: 'bench', sets: [SetLog(w: 95, r: 5, done: true)]))!;
      expect(rec.est, 110.8);
      expect(rec.w, 95);
      expect(rec.r, 5);
      expect(rec.prev, 105);
    });

    test('stays quiet when the session does not beat the record', () {
      expect(
          is1RMRecord(
              s, 'bench', WorkoutEntry(id: 'bench', sets: [SetLog(w: 90, r: 5, done: true)])),
          isNull);
      expect(
          is1RMRecord(
              s, 'bench', WorkoutEntry(id: 'bench', sets: [SetLog(w: 80, r: 5, done: true)])),
          isNull);
    });

    test('counts the first ever estimate as a record', () {
      final rec = is1RMRecord(s, 'deadlift',
          WorkoutEntry(id: 'deadlift', sets: [SetLog(w: 140, r: 3, done: true)]))!;
      expect(rec.prev, 0);
      expect(rec.est, 154);
    });

    test('says nothing for a timed or unfinished entry', () {
      expect(is1RMRecord(s, 'plank', WorkoutEntry(id: 'plank', sets: [SetLog(sec: 90, done: true)])),
          isNull);
      expect(
          is1RMRecord(
              s, 'bench', WorkoutEntry(id: 'bench', sets: [SetLog(w: 200, r: 5, done: false)])),
          isNull);
    });
  });
}
