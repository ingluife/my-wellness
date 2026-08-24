import 'package:flutter_test/flutter_test.dart';
import 'package:my_open_gym/data/models/app_state.dart';
import 'package:my_open_gym/domain/effort.dart';
import 'package:my_open_gym/domain/format.dart';

/// Ported from openGym/frontend/src/lib/effort.test.js.
void main() {
  DateTime daysAgo(int n) {
    final d = DateTime.now();
    return DateTime(d.year, d.month, d.day - n, 12);
  }

  /// One workout on a day, with the sets given. Everything here is a finished set unless a set
  /// says otherwise, because that is what the stats read.
  Workout w(int n, List<SetLog> sets) {
    final d = daysAgo(n);
    return Workout(
      id: 'w$n',
      d: isoOf(d),
      start: d.millisecondsSinceEpoch,
      end: d.millisecondsSinceEpoch,
      name: '',
      entries: [WorkoutEntry(id: '0025', sets: sets)],
    );
  }

  /// The defaults every set in this suite carries unless overridden.
  SetLog st({double? rir, double? rpe, bool done = true}) =>
      SetLog(w: 60, r: 8, done: done, rir: rir, rpe: rpe);

  AppState s(List<Workout> workouts) => AppState(workouts: workouts);

  group('rirOf', () {
    test('reads RIR straight and RPE as its mirror — RPE 8 is RIR 2', () {
      expect(rirOf(SetLog(rir: 2)), 2);
      expect(rirOf(SetLog(rpe: 8)), 2);
      expect(rirOf(SetLog(rpe: 9.5)), 0.5);
    });

    test('keeps a rated 0 and rejects everything that only looks like one', () {
      // Taken to failure — a rating, not "empty".
      expect(rirOf(SetLog(rir: 0)), 0);
      expect(rirOf(SetLog(rpe: 10)), 0);
      expect(rirOf(SetLog()), isNull);
      expect(rirOf(null), isNull);
    });

    test('prefers the scale the set itself was logged on when a file wrote both', () {
      expect(rirOf(SetLog(rir: 3, rpe: 9)), 3);
    });
  });

  group('toScale', () {
    test('converts back to whichever scale is on screen', () {
      expect(toScale('rir', 2), 2);
      expect(toScale('rpe', 2), 8);
      expect(toScale('rpe', 0), 10);
      expect(toScale('rir', null), isNull);
    });

    test('does not let the round trip produce float dust', () {
      expect(toScale('rpe', 10 - 7.5), 7.5);
    });
  });

  group('displayScale', () {
    test('follows the profile setting when it has one', () {
      expect(displayScale(AppState(effort: 'rpe')), 'rpe');
      expect(displayScale(AppState(effort: 'rir')), 'rir');
    });

    test('shows an unrated profile the scale its imported history is written in', () {
      // Effort off, but a file brought RPE with it: labelling that history "RIR" would show a
      // number the profile has never entered and mean the opposite of what it says.
      expect(
          displayScale(AppState(effort: 'none', workouts: [w(3, [st(rpe: 8), st(rpe: 9)])])),
          'rpe');
      expect(displayScale(AppState(effort: 'none', workouts: [w(3, [st(rir: 2)])])), 'rir');
      expect(displayScale(AppState(effort: 'none')), 'rir');
    });
  });

  group('avgRir', () {
    test('averages the rated sets and ignores the rest', () {
      expect(avgRir([SetLog(rir: 1), SetLog(rir: 3)]), 2);
      // RPE 7 = RIR 3.
      expect(avgRir([SetLog(rir: 1), SetLog(), SetLog(rpe: 7)]), 2);
    });

    test('is null rather than 0 when nothing was rated', () {
      expect(avgRir([SetLog(), SetLog()]), isNull);
      expect(avgRir([]), isNull);
      expect(avgRir(null), isNull);
    });
  });

  group('effortSummary', () {
    AppState state() => s([
          w(2, [st(rir: 1), st(rir: 3), st(rir: 2)]),
          // RPE 6 = RIR 4, one set unrated.
          w(4, [st(rir: 0), st(rpe: 6), st()]),
          w(40, [st(rir: 5), st(rir: 5)]),
        ]);

    test('counts rated sets against every finished set, not against itself', () {
      final r = effortSummary(state(), 0);
      expect(r.done, 8);
      expect(r.rated, 7);
    });

    test('leaves unrated sets out of the average instead of reading them as failure', () {
      final r = effortSummary(
          s([w(2, [st(rir: 4), st(), st(), st(), st(), st()])]), 0);
      expect(r.rated, 1);
      // One rating is not an average.
      expect(r.avg, isNull);
    });

    test('waits for a real sample before reporting a number', () {
      final few = s([w(2, [for (var i = 0; i < minRated - 1; i++) st(rir: 2)])]);
      expect(effortSummary(few, 0).avg, isNull);
      final enough = s([w(2, [for (var i = 0; i < minRated; i++) st(rir: 2)])]);
      expect(effortSummary(enough, 0).avg, 2);
    });

    test('counts the sets taken close to failure', () {
      final r = effortSummary(state(), 0);
      // 1, 3, 2, 0 — the 4 and the two 5s are not.
      expect(r.hard, 4);
      expect(r.hardPct, closeTo(4 / 7, 1e-9));
    });

    test('honours the window', () {
      // The 40-day-old session is out.
      expect(effortSummary(state(), 7).rated, 5);
      expect(effortSummary(state(), 3).rated, 3);
    });

    test('survives a profile with no training at all', () {
      final r = effortSummary(AppState(), 30);
      expect(r.done, 0);
      expect(r.rated, 0);
      expect(r.hard, 0);
      expect(r.avg, isNull);
      expect(r.hardPct, isNull);
    });
  });

  group('hasEffort', () {
    test('decides whether the effort UI exists at all', () {
      expect(hasEffort(s([w(2, [st(rir: 0)])])), isTrue);
      expect(hasEffort(s([w(2, [st(rpe: 8)])])), isTrue);
      expect(hasEffort(s([w(2, [st(), st()])])), isFalse);
      expect(hasEffort(AppState()), isFalse);
    });

    test('ignores sets that were never finished', () {
      expect(hasEffort(s([w(2, [st(rir: 2, done: false)])])), isFalse);
    });
  });

  group('effortWeeks', () {
    test('averages per calendar week and carries the week volume alongside', () {
      final pts = effortWeeks(s([w(1, [st(rir: 1), st(rir: 3), st()])]), 0);
      expect(pts, hasLength(1));
      expect(pts[0].rir, 2);
      // Rated, then trained.
      expect(pts[0].n, 2);
      expect(pts[0].sets, 3);
    });

    test('drops a week that rests on a single tap', () {
      expect(effortWeeks(s([w(1, [st(rir: 1)])]), 0), isEmpty);
    });

    test('comes back oldest first, whatever order the workouts arrived in', () {
      final pts = effortWeeks(
          s([w(2, [st(rir: 1), st(rir: 1)]), w(30, [st(rir: 3), st(rir: 3)])]), 0);
      expect(pts.map((p) => p.rir), [3, 1]);
      expect(pts[0].t, lessThan(pts[1].t));
    });
  });

  group('effortHistogram', () {
    test('bins by whole steps and collapses the far end into a tail', () {
      final h = effortHistogram(
          s([w(2, [st(rir: 0), st(rir: 1.5), st(rir: 4), st(rir: 7)])]), 0);
      expect(h.map((b) => b.n), [1, 1, 0, 0, 2]);
      expect(h[4].tail, isTrue);
      expect(h[0].pct, 0.25);
    });

    test('is all zeroes, not NaN, when nothing is rated', () {
      final h = effortHistogram(s([w(2, [st()])]), 0);
      expect(h.every((b) => b.n == 0 && b.pct == 0), isTrue);
    });
  });

  group('isHardSet', () {
    test('draws the line at the effort that actually drives adaptation', () {
      expect(isHardSet(SetLog(rir: hardRir)), isTrue);
      expect(isHardSet(SetLog(rir: hardRir + 0.5)), isFalse);
      expect(isHardSet(SetLog(rpe: 10)), isTrue);
      // Unrated is not hard, and not easy either.
      expect(isHardSet(SetLog()), isFalse);
    });
  });
}
