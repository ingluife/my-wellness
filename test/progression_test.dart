import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/exercises.dart';
import 'package:my_wellness/domain/progression.dart';

import 'helpers.dart';

/// Ported from openGym/frontend/src/lib/progression.test.js, assertion for assertion.
///
/// These are the tests that catch translation drift: the progression engine is where "looks
/// right" and "is right" diverge silently, and a wrong deload only shows up as a bad session
/// weeks later.
void main() {
  setUpAll(loadExercises);

  // An exercise whose body part takes the small increment, one that takes the big one, and a
  // cardio exercise — picked out of the real dataset, as the JS suite does.
  late String lift, heavy, cardio;

  setUpAll(() {
    const heavyBp = ['upper legs', 'lower legs', 'back', 'hips', 'glutes'];
    lift = exdb.db.firstWhere((e) => e.bp != 'cardio' && !heavyBp.contains(e.bp)).id;
    heavy = exdb.db.firstWhere((e) => e.bp == 'upper legs').id;
    cardio = exdb.db.firstWhere((e) => e.bp == 'cardio').id;
  });

  /// A state whose history is a list of sessions given as [weight, ...repsPerSet].
  /// A rep count of null means "the set was never checked off".
  AppState hist(String id, List<List<double?>> rows, [ExerciseConfig? target]) => AppState(
        workouts: [
          for (var i = 0; i < rows.length; i++)
            Workout(
              id: 'w$i',
              d: '2026-01-0${i + 1}',
              start: 0,
              end: 0,
              name: '',
              entries: [
                WorkoutEntry(
                  id: id,
                  target: target ??
                      ExerciseConfig(sets: 3, reps: 5, weight: rows[i][0]),
                  sets: [
                    for (final r in rows[i].skip(1))
                      r == null
                          ? SetLog(w: rows[i][0], r: 0, done: false)
                          : SetLog(w: rows[i][0], r: r, done: true)
                  ],
                )
              ],
            )
        ],
      );

  group('readSession', () {
    final tgt = ExerciseConfig(sets: 3, reps: 5);

    test('counts a session where every set made its reps as a hit', () {
      final s = readSession(
          WorkoutEntry(id: lift, target: tgt, sets: [
            SetLog(w: 60, r: 5, done: true),
            SetLog(w: 60, r: 5, done: true),
            SetLog(w: 60, r: 6, done: true),
          ]),
          null);
      expect(s.ok, isTrue);
      expect(s.weight, 60);
      expect(s.amrap, 6);
      expect(s.low, 5);
    });

    test('counts short reps as a miss even when the set was checked off', () {
      final s = readSession(
          WorkoutEntry(id: lift, target: tgt, sets: [
            SetLog(w: 60, r: 5, done: true),
            SetLog(w: 60, r: 5, done: true),
            SetLog(w: 60, r: 3, done: true),
          ]),
          null);
      expect(s.ok, isFalse);
    });

    test('counts an unchecked set as a miss — it was not performed', () {
      final s = readSession(
          WorkoutEntry(id: lift, target: tgt, sets: [
            SetLog(w: 60, r: 5, done: true),
            SetLog(w: 60, r: 5, done: true),
            SetLog(w: 60, r: 0, done: false),
          ]),
          null);
      expect(s.ok, isFalse);
      // The working weight is still known from the sets that counted.
      expect(s.weight, 60);
    });

    test('counts fewer sets than prescribed as a miss', () {
      final s = readSession(
          WorkoutEntry(id: lift, target: tgt, sets: [
            SetLog(w: 60, r: 5, done: true),
            SetLog(w: 60, r: 5, done: true),
          ]),
          null);
      expect(s.ok, isFalse);
    });

    test('refuses to call a session a hit when nothing was prescribed', () {
      final s = readSession(
          WorkoutEntry(id: lift, target: ExerciseConfig(), sets: [SetLog(w: 60, r: 5, done: true)]),
          null);
      expect(s.ok, isFalse);
    });

    test('reads a timed session by the hold, not by reps', () {
      final t = ExerciseConfig(sets: 2, sec: 45, mode: 'time');
      final s = readSession(
          WorkoutEntry(id: lift, target: t, sets: [
            SetLog(sec: 45, w: 0, done: true),
            SetLog(sec: 50, w: 0, done: true),
          ]),
          null);
      expect(s.mode, 'time');
      expect(s.ok, isTrue);
      expect(s.best, 50);

      final short = readSession(
          WorkoutEntry(id: lift, target: t, sets: [
            SetLog(sec: 45, done: true),
            SetLog(sec: 30, done: true),
          ]),
          null);
      expect(short.ok, isFalse);
    });
  });

  group('stallCount', () {
    test('counts consecutive misses back from the most recent session', () {
      expect(stallCount([okSession(true), okSession(true)]), 0);
      expect(stallCount([okSession(true), okSession(false)]), 1);
      expect(stallCount([okSession(false), okSession(false), okSession(false)]), 3);
      expect(stallCount([okSession(false), okSession(true), okSession(false)]), 1);
      expect(stallCount([]), 0);
    });
  });

  group('policyFor', () {
    test("keeps the app's long-standing behaviour as the default for reps work", () {
      expect(policyFor(ExerciseConfig(id: lift), null, 'reps'), 'linear');
    });

    test('leaves timed and cardio work alone unless asked', () {
      expect(policyFor(ExerciseConfig(id: lift, mode: 'time'), null, 'time'), 'off');
      expect(policyFor(ExerciseConfig(id: cardio), null, 'cardio'), 'off');
    });

    test('lets the exercise override the routine, and the routine override the default', () {
      final r = Routine(id: 'r', name: '', prog: 'greyskull');
      expect(policyFor(ExerciseConfig(id: lift), r, 'reps'), 'greyskull');
      expect(policyFor(ExerciseConfig(id: lift, prog: 'double'), r, 'reps'), 'double');
    });

    test('refuses a policy that makes no sense for the mode', () {
      expect(policyFor(ExerciseConfig(id: lift, mode: 'time', prog: 'greyskull'), null, 'time'), 'off');
      expect(policyFor(ExerciseConfig(id: cardio, prog: 'linear'), null, 'cardio'), 'off');
      expect(policiesFor['cardio'], ['off']);
    });
  });

  group('defaultIncrement', () {
    test('gives lower-body lifts the bigger jump', () {
      expect(defaultIncrement(lift, 'kg'), 2.5);
      expect(defaultIncrement(heavy, 'kg'), 5);
    });
    test('scales to pounds', () {
      expect(defaultIncrement(lift, 'lb'), 5);
      expect(defaultIncrement(heavy, 'lb'), 10);
    });
    test('falls back for an unknown exercise', () {
      expect(defaultIncrement('nope', 'kg'), 2.5);
    });
  });

  group('linear progression', () {
    ExerciseConfig cfg() =>
        ExerciseConfig(id: lift, sets: 3, reps: 5, weight: 60, prog: 'linear');

    test('says nothing useful before there is any history', () {
      final p = nextPrescription(AppState(), cfg(), null);
      expect(p.kind, 'first');
      expect(p.weight, isNull);
    });

    test('adds the increment after a clean session', () {
      final p = nextPrescription(hist(lift, [[60, 5, 5, 5]]), cfg(), null);
      expect(p.kind, 'up');
      expect(p.weight, 62.5);
    });

    test('repeats the weight after a miss instead of advancing', () {
      final p = nextPrescription(hist(lift, [[60, 5, 5, 3]]), cfg(), null);
      expect(p.kind, 'hold');
      expect(p.weight, 60);
    });

    test('does not advance when the last set was left unchecked', () {
      final p = nextPrescription(hist(lift, [[60, 5, 5, null]]), cfg(), null);
      expect(p.kind, 'hold');
      expect(p.weight, 60);
    });

    test('deloads after three misses in a row, onto a loadable weight', () {
      final p = nextPrescription(
          hist(lift, [[60, 5, 5, 3], [60, 5, 4, 4], [60, 5, 5, 4]]), cfg(), null);
      expect(p.kind, 'deload');
      // 60 x 0.9 = 54 -> nearest loadable 2.5 step
      expect(p.weight, 55);
      expect(deloadAfter['linear'], 3);
    });

    test('a good session in between clears the stall', () {
      final p = nextPrescription(
          hist(lift, [[60, 5, 5, 3], [60, 5, 5, 5], [60, 5, 5, 3]]), cfg(), null);
      expect(p.kind, 'hold');
    });

    test('never deloads below one increment, however light the lift already is', () {
      final p = nextPrescription(
          hist(lift, [[2.5, 1, 1, 1], [2.5, 1, 1, 1], [2.5, 1, 1, 1]]), cfg(), null);
      expect(p.kind, 'deload');
      expect(p.weight, 2.5);
    });

    test('always makes a deload actually lighter, even when rounding would not', () {
      // 20 x 0.9 = 18 -> nearest 2.5 step is 17.5, fine. 5 x 0.9 = 4.5 -> nearest step is 5,
      // which is no deload at all, so it has to step down instead.
      final p = nextPrescription(
          hist(lift, [[5, 1, 1, 1], [5, 1, 1, 1], [5, 1, 1, 1]]), cfg(), null);
      expect(p.weight, lessThan(5));
    });

    test('uses the heavier step for a lower-body lift', () {
      final p = nextPrescription(hist(heavy, [[100, 5, 5, 5]]),
          ExerciseConfig(id: heavy, sets: 3, reps: 5, prog: 'linear'), null);
      expect(p.weight, 105);
    });

    test('honours a per-exercise increment override', () {
      final p = nextPrescription(hist(lift, [[60, 5, 5, 5]]), cfg()..inc = 1, null);
      expect(p.weight, 61);
    });

    test('works in pounds', () {
      final s = hist(lift, [[135, 5, 5, 5]])..unit = 'lb';
      expect(nextPrescription(s, cfg(), null).weight, 140);
    });
  });

  group('bodyweight exercises', () {
    ExerciseConfig cfg() =>
        ExerciseConfig(id: lift, sets: 3, reps: 10, weight: 0, prog: 'linear');
    AppState bw(List<List<double?>> rows) =>
        hist(lift, rows, ExerciseConfig(sets: 3, reps: 10));

    test('never invents a weight to deload to — there is nothing to take off a push-up', () {
      final p = nextPrescription(
          bw([[0, 10, 10, 8], [0, 10, 10, 9], [0, 10, 10, 8]]), cfg(), null);
      expect(p.kind, 'hold');
      expect(p.weight, 0);
      expect(p.reps, 10);
    });

    test('progresses in reps instead of load after a clean session', () {
      final p = nextPrescription(bw([[0, 10, 10, 10]]), cfg(), null);
      expect(p.kind, 'up');
      expect(p.weight, 0);
      expect(p.reps, 11);
    });

    test('climbs to the ceiling one rep at a time', () {
      final p = nextPrescription(bw([[0, 10, 10, 10]]), cfg()..repsMax = 15, null);
      expect(p.kind, 'up');
      expect(p.reps, 11);
      expect(p.sets, isNull);
    });

    test('adds a set and restarts the range once the ceiling is reached', () {
      final at15 = hist(lift, [[0, 15, 15, 15]], ExerciseConfig(sets: 3, reps: 15));
      final p = nextPrescription(at15, cfg()..reps = 10..repsMax = 15, null);
      expect(p.kind, 'up');
      expect(p.sets, 4);
      expect(p.reps, 10);
      expect(p.weight, 0);
    });

    test('stops adding sets at the cap and says what to do instead', () {
      final at15 = hist(lift, [[0, 15, 15, 15]], ExerciseConfig(sets: 3, reps: 15));
      final p = nextPrescription(
          at15, cfg()..sets = maxBwSets.toDouble()..reps = 10..repsMax = 15, null);
      expect(p.kind, 'hold');
      expect(p.sets, isNull);
      expect(p.why!.first, contains('harder variation'));
    });

    test('leaves a belted set to the normal policies — there is a load to add now', () {
      final belted = hist(lift, [[10, 10, 10, 10]], ExerciseConfig(sets: 3, reps: 10));
      final p = nextPrescription(belted, cfg()..bodyweight = true..repsMax = 15, null);
      expect(p.kind, 'up');
      expect(p.weight, greaterThan(10));
      expect(p.sets, isNull);
    });

    test('steps a unilateral total by two, so it lands on 16, 18, 20', () {
      final at16 = hist(lift, [[0, 16, 16, 16]], ExerciseConfig(sets: 3, reps: 16));
      expect(nextPrescription(at16, cfg()..reps = 16..side = true, null).reps, 18);
      // ...and by one when it is not.
      expect(nextPrescription(at16, cfg()..reps = 16, null).reps, 17);
    });

    test('keeps climbing reps forever when no ceiling was set — the old behaviour', () {
      final at30 = hist(lift, [[0, 30, 30, 30]], ExerciseConfig(sets: 3, reps: 30));
      final p = nextPrescription(at30, cfg(), null);
      expect(p.kind, 'up');
      expect(p.reps, 31);
      expect(p.sets, isNull);
    });

    test('applies to every policy, not just linear', () {
      for (final prog in ['linear', 'greyskull', 'double']) {
        final p = nextPrescription(
            bw([[0, 10, 10, 4], [0, 10, 10, 4], [0, 10, 10, 4]]), cfg()..prog = prog, null);
        expect(p.weight, 0, reason: prog);
        expect(p.kind, 'hold', reason: prog);
      }
    });

    test('still adds load the moment the exercise is actually weighted', () {
      final p = nextPrescription(
          hist(lift, [[10, 10, 10, 10]], ExerciseConfig(sets: 3, reps: 10)), cfg(), null);
      expect(p.kind, 'up');
      expect(p.weight, 12.5);
    });
  });

  group('Greyskull LP', () {
    ExerciseConfig cfg() =>
        ExerciseConfig(id: lift, sets: 3, reps: 5, weight: 60, prog: 'greyskull');

    test('advances when the final set makes the target', () {
      final p = nextPrescription(hist(lift, [[60, 5, 5, 5]]), cfg(), null);
      expect(p.kind, 'up');
      expect(p.weight, 62.5);
    });

    test('takes a double jump when the last set doubles the target reps', () {
      final p = nextPrescription(hist(lift, [[60, 5, 5, 10]]), cfg(), null);
      expect(p.kind, 'up');
      expect(p.weight, 65);
      expect(p.why!.first, contains('double'));
    });

    test('resets 10 % on the very first failure, unlike plain linear', () {
      final p = nextPrescription(hist(lift, [[60, 5, 5, 3]]), cfg(), null);
      expect(p.kind, 'deload');
      expect(p.weight, 55);
      expect(deloadAfter['greyskull'], 1);
    });

    test('keeps resetting from the reduced weight, not the original', () {
      final p = nextPrescription(hist(lift, [[60, 5, 5, 3], [55, 5, 5, 2]]), cfg(), null);
      expect(p.kind, 'deload');
      // 55 x 0.9 = 49.5 -> nearest loadable 2.5 step
      expect(p.weight, 50);
    });
  });

  group('double progression', () {
    ExerciseConfig cfg() => ExerciseConfig(
        id: lift, sets: 3, reps: 12, repsMin: 8, weight: 40, prog: 'double');
    final tgt = ExerciseConfig(sets: 3, reps: 12);

    test('adds weight and drops back to the bottom of the range at the top of it', () {
      final p = nextPrescription(hist(lift, [[40, 12, 12, 12]], tgt), cfg(), null);
      expect(p.kind, 'up');
      expect(p.weight, 42.5);
      expect(p.reps, 8);
    });

    test('keeps the weight and asks for one more rep while inside the range', () {
      final p = nextPrescription(hist(lift, [[40, 10, 9, 9]], tgt), cfg(), null);
      expect(p.kind, 'hold');
      expect(p.weight, 40);
      // Worst set was 9 -> aim for 10.
      expect(p.reps, 10);
    });

    test('never asks for more than the top of the range', () {
      final p = nextPrescription(hist(lift, [[40, 12, 12, 11]], tgt), cfg(), null);
      expect(p.reps, lessThanOrEqualTo(12));
    });

    test('deloads after a run of stalls and restarts at the bottom of the range', () {
      final rows = [[40.0, 9.0, 9.0, 9.0], [40.0, 9.0, 9.0, 9.0], [40.0, 9.0, 9.0, 9.0]];
      final p = nextPrescription(hist(lift, rows, tgt), cfg(), null);
      expect(p.kind, 'deload');
      expect(p.reps, 8);
      // 40 x 0.9 = 36 -> nearest loadable 2.5 step
      expect(p.weight, 35);
    });
  });

  group('timed progression', () {
    ExerciseConfig cfg() =>
        ExerciseConfig(id: lift, mode: 'time', sets: 2, sec: 45, prog: 'time');
    final tgt = ExerciseConfig(sets: 2, sec: 45, mode: 'time');

    AppState timeHist(List<List<double>> rows) => AppState(
          workouts: [
            for (var i = 0; i < rows.length; i++)
              Workout(
                id: 'w$i',
                d: '2026-02-0${i + 1}',
                start: 0,
                end: 0,
                name: '',
                entries: [
                  WorkoutEntry(
                    id: lift,
                    target: tgt,
                    sets: [for (final sec in rows[i]) SetLog(sec: sec, w: 0, done: true)],
                  )
                ],
              )
          ],
        );

    test('adds time when every set went the full duration', () {
      final p = nextPrescription(timeHist([[45, 45]]), cfg(), null);
      expect(p.kind, 'up');
      expect(p.sec, 50);
      expect(p.weight, isNull);
    });

    test('repeats the target when a hold came up short', () {
      final p = nextPrescription(timeHist([[45, 38]]), cfg(), null);
      expect(p.kind, 'hold');
      expect(p.sec, 45);
    });

    test('backs the target off after a run of short sessions', () {
      final p = nextPrescription(timeHist([[45, 30], [45, 32], [45, 31]]), cfg(), null);
      expect(p.kind, 'deload');
      // 45 x 0.9 = 40.5 -> nearest 5 s step
      expect(p.sec, 40);
    });

    test('ignores reps history when the exercise switched to time', () {
      final p = nextPrescription(hist(lift, [[60, 5, 5, 5]]), cfg(), null);
      // No timed session yet, so no opinion.
      expect(p.kind, 'first');
    });
  });

  group('policy "off"', () {
    test('has no opinion at all', () {
      final p = nextPrescription(hist(lift, [[60, 5, 5, 5]]),
          ExerciseConfig(id: lift, sets: 3, reps: 5, prog: 'off'), null);
      expect(p.kind, 'off');
      expect(p.weight, isNull);
    });

    test('is what cardio always gets', () {
      final p = nextPrescription(
          AppState(), ExerciseConfig(id: cardio, sets: 1, min: 20), null);
      expect(p.kind, 'off');
    });
  });

  group('sessionsFor', () {
    test('skips workouts where the exercise was never actually logged', () {
      final s = AppState(workouts: [
        wk('2026-01-01', [
          WorkoutEntry(
              id: lift,
              target: ExerciseConfig(sets: 1, reps: 5),
              sets: [SetLog(w: 60, r: 5, done: true)])
        ]),
        wk('2026-01-02', [
          WorkoutEntry(
              id: lift,
              target: ExerciseConfig(sets: 1, reps: 5),
              sets: [SetLog(w: 60, r: 0, done: false)])
        ]),
        wk('2026-01-03', [
          WorkoutEntry(
              id: 'other',
              target: ExerciseConfig(),
              sets: [SetLog(w: 20, r: 5, done: true)])
        ]),
      ]);
      expect(sessionsFor(s, lift, null).map((x) => x.d), ['2026-01-01']);
    });

    test('reads a legacy entry that has no target without crashing', () {
      final s = AppState(workouts: [
        wk('2026-01-01', [WorkoutEntry(id: lift, sets: [SetLog(w: 60, r: 5, done: true)])])
      ]);
      expect(sessionsFor(s, lift, null), hasLength(1));
    });
  });

  // Workouts only began storing their prescription in v1.2.2. Everything logged before that is
  // targetless, and reading it as "missed" would tell every long-standing user to deload on
  // their first session after updating.
  group('history logged before targets were recorded', () {
    AppState legacy(List<List<double>> rows) => AppState(
          workouts: [
            for (var i = 0; i < rows.length; i++)
              wk('2026-03-${(i + 1).toString().padLeft(2, '0')}', [
                // No target.
                WorkoutEntry(
                  id: lift,
                  sets: [for (final r in rows[i].skip(1)) SetLog(w: rows[i][0], r: r, done: true)],
                )
              ])
          ],
        );
    ExerciseConfig cfg() =>
        ExerciseConfig(id: lift, sets: 3, reps: 5, weight: 60, prog: 'linear');

    test('judges a targetless session against the current plan instead of calling it a miss', () {
      final p = nextPrescription(legacy([[60, 5, 5, 5]]), cfg(), null);
      expect(p.kind, 'up');
      expect(p.weight, 62.5);
    });

    test('does not manufacture a stall out of a long clean history', () {
      final p = nextPrescription(
          legacy(List.generate(11, (_) => [60.0, 5.0, 5.0, 5.0])), cfg(), null);
      expect(p.kind, 'up');
    });

    test('still spots a genuine miss in old data', () {
      expect(nextPrescription(legacy([[60, 5, 5, 2]]), cfg(), null).kind, 'hold');
    });

    test('matches the weight hint the app showed before this engine existed', () {
      // Old rule: every set at or above the plan's reps, with a real weight -> suggest a step up.
      expect(nextPrescription(legacy([[60, 5, 6, 5]]), cfg(), null).weight, 62.5);
      expect(nextPrescription(legacy([[60, 5, 4, 5]]), cfg(), null).kind, 'hold');
    });
  });

  group('applyPrescription', () {
    List<SetLog> sets() =>
        [SetLog(w: 60, r: 5, done: true), SetLog(w: 60, r: 5, done: false)];

    test('rewrites only what the policy decided, and only unlogged sets', () {
      final out = applyPrescription(sets(), Prescription(kind: 'up', weight: 62.5));
      expect(out[0].toJson(), {'w': 60, 'r': 5, 'done': true});
      expect(out[1].toJson(), {'w': 62.5, 'r': 5, 'done': false});
    });

    test('sets reps too when the policy has an opinion about them', () {
      final out = applyPrescription(sets(), Prescription(kind: 'up', weight: 42.5, reps: 8));
      expect(out[1].toJson(), {'w': 42.5, 'r': 8, 'done': false});
    });

    test('touches nothing for "off" or a first session', () {
      final s = sets();
      expect(applyPrescription(s, Prescription(kind: 'off')), same(s));
      expect(applyPrescription(s, Prescription(kind: 'first')), same(s));
      expect(applyPrescription(s, null), same(s));
    });

    test('adjusts a timed set without inventing a weight', () {
      final timed = [SetLog(sec: 45, w: 0, done: false)];
      final out = applyPrescription(timed, Prescription(kind: 'up', sec: 50));
      expect(out.map((s) => s.toJson()), [
        {'w': 0, 'sec': 50, 'done': false}
      ]);
    });

    test('grows the list when the policy added a set', () {
      final three = [
        SetLog(w: 0, r: 10, done: false),
        SetLog(w: 0, r: 10, done: false),
        SetLog(w: 0, r: 10, done: false),
      ];
      final out =
          applyPrescription(three, Prescription(kind: 'up', weight: 0, reps: 10, sets: 4));
      expect(out, hasLength(4));
      expect(out[3].toJson(), {'w': 0, 'r': 10, 'done': false});
    });

    test('never shrinks a session that has already logged sets', () {
      final s = sets();
      expect(applyPrescription(s, Prescription(kind: 'up', weight: 60, sets: 1)), hasLength(s.length));
    });
  });
}
