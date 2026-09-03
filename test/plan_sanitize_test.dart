import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/domain/ai/plan_draft.dart';
import 'package:my_wellness/domain/ai/plan_sanitize.dart';
import 'package:my_wellness/domain/ai/plan_scope.dart';
import 'package:my_wellness/domain/exercises.dart';

import 'helpers.dart';

/// Everything a model can return that the app must not act on.
///
/// The boundary this file guards: a routine is built from catalogue ids, never from anything the
/// model wrote. Nothing here may throw — the input is whatever a third party sent back.
void main() {
  setUpAll(loadExercises);

  // Real dataset ids, so the lookup is the real thing rather than a stub that agrees with itself.
  const curl = '0031'; // barbell curl — tg biceps
  const hammer = '0313'; // dumbbell hammer curl — tg biceps
  const squat = '0043'; // barbell full squat — upper legs, nothing to do with biceps

  PlanDraft run(Object? raw, {PlanScope scope = const PlanScope.fullBody()}) =>
      sanitizePlanDraft(raw, lookup: (id) => exdb[id], scope: scope);

  Map<String, Object?> plan(List<Map<String, Object?>> exercises, {String name = 'Arms'}) => {
        'routines': [
          {'name': name, 'exercises': exercises}
        ],
      };

  Map<String, Object?> ex(String id, {Object? sets = 3, Object? reps = 10}) =>
      {'id': id, 'sets': sets, 'reps': reps};

  group('the envelope', () {
    test('anything that is not the agreed shape is empty, never a throw', () {
      for (final raw in <Object?>[
        null,
        'a plan',
        42,
        [],
        <String, Object?>{},
        {'routines': null},
        {'routines': []},
        {'routines': 'Push day'},
        {'routines': [42, 'nonsense']},
      ]) {
        final d = run(raw);
        expect(d.isEmpty, isTrue, reason: '$raw');
        expect(d.problems, isNotEmpty, reason: '$raw');
      }
    });

    test('a routine whose exercises all fail leaves no empty routine behind', () {
      final d = run(plan([ex('not-an-id'), ex('9999')]));
      expect(d.isEmpty, isTrue);
      expect(d.problems, contains(PlanProblem.unknownExercise));
      expect(d.problems, contains(PlanProblem.noRoutines));
    });
  });

  group('ids', () {
    test('an invented id is dropped, not turned into a placeholder', () {
      // The whole point. A routine holding an exercise the app cannot show, animate or progress
      // is worse than a shorter routine.
      final d = run(plan([ex(curl), ex('made-up'), ex(hammer)]));
      expect(d.routines.single.exercises.map((e) => e.id), [curl, hammer]);
      expect(d.problems, contains(PlanProblem.unknownExercise));
    });

    test('the name comes from the dataset, never from the answer', () {
      final d = run({
        'routines': [
          {
            'name': 'Arms',
            'exercises': [
              {'id': curl, 'sets': 3, 'reps': 10, 'name': 'Ultimate Mega Curl'}
            ],
          }
        ],
      });
      expect(d.routines.single.exercises.single.name, exdb[curl]!.n);
    });

    test('an out-of-scope id is dropped even though it resolves', () {
      // A squat is a real exercise; it is not a biceps exercise. The catalogue the model was given
      // was already filtered, so anything failing here was invented or misread.
      final d = run(plan([ex(curl), ex(squat)]), scope: const PlanScope.target('biceps'));
      expect(d.routines.single.exercises.map((e) => e.id), [curl]);
      expect(d.problems, contains(PlanProblem.outOfScope));
    });

    test('the same exercise twice in one routine keeps the first', () {
      final d = run(plan([ex(curl, sets: 4), ex(curl, sets: 9)]));
      final only = d.routines.single.exercises.single;
      expect(only.id, curl);
      expect(only.sets, 4);
      expect(d.problems, contains(PlanProblem.duplicate));
    });
  });

  group('prescriptions', () {
    test('nonsense sets and reps are clamped rather than rejected', () {
      final d = run(plan([
        ex(curl, sets: 0, reps: 500),
        ex(hammer, sets: 99, reps: -3),
      ]));
      final list = d.routines.single.exercises;
      expect(list[0].sets, 1);
      expect(list[0].reps, 50);
      expect(list[1].sets, 10);
      expect(list[1].reps, 1);
      expect(d.problems, contains(PlanProblem.clamped));
    });

    test('a missing or non-numeric prescription falls back to something usable', () {
      final d = run(plan([
        {'id': curl},
        {'id': hammer, 'sets': 'three', 'reps': double.nan},
      ]));
      for (final e in d.routines.single.exercises) {
        expect(e.sets, 3);
        expect(e.reps, 10);
      }
      expect(d.problems, contains(PlanProblem.clamped));
    });

    test('a rep range survives only when it is one', () {
      final ok = run(plan([
        {'id': curl, 'sets': 3, 'reps': 10, 'repsMin': 8, 'repsMax': 12}
      ])).routines.single.exercises.single;
      expect(ok.repsMin, 8);
      expect(ok.repsMax, 12);

      // Inverted: which of the two was meant is not knowable, so neither is kept.
      final bad = run(plan([
        {'id': curl, 'sets': 3, 'reps': 10, 'repsMin': 12, 'repsMax': 8}
      ])).routines.single.exercises.single;
      expect(bad.repsMin, isNull);
      expect(bad.repsMax, isNull);
    });

    test('a drafted exercise becomes a config the rest of the app understands', () {
      // defaultConfig fills in mode and the bodyweight flag, which is what makes a drafted
      // exercise behave identically to a hand-added one under progression.
      final cfg = run(plan([ex(curl, sets: 4, reps: 8)])).routines.single.exercises.single.toConfig();
      expect(cfg.id, curl);
      expect(cfg.sets, 4);
      expect(cfg.reps, 8);
    });
  });

  group('caps', () {
    test('more exercises than a session can hold drops the tail', () {
      final many = exdb.db.where((e) => e.bp == 'upper arms').take(20).map((e) => ex(e.id));
      final d = run(plan(many.toList()));
      expect(d.routines.single.exercises, hasLength(12));
      expect(d.problems, contains(PlanProblem.tooMany));
    });

    test('more routines than a week has days drops the tail', () {
      final d = run({
        'routines': [
          for (var i = 0; i < 10; i++)
            {
              'name': 'Day $i',
              'exercises': [ex(curl)]
            }
        ],
      });
      expect(d.routines, hasLength(7));
      expect(d.problems, contains(PlanProblem.tooMany));
    });
  });

  group('the week map', () {
    Map<String, Object?> twoDayPlan(Object? week) => {
          'routines': [
            {
              'name': 'A',
              'exercises': [ex(curl)]
            },
            {
              'name': 'B',
              'exercises': [ex(hammer)]
            },
          ],
          'week': week,
        };

    test('valid weekday mappings come through', () {
      final d = run(twoDayPlan({'1': 0, '4': 1}));
      expect(d.week, {'1': 0, '4': 1});
      expect(d.problems, isEmpty);
    });

    test('an index past the end of the routines is dropped', () {
      final d = run(twoDayPlan({'1': 0, '3': 7}));
      expect(d.week, {'1': 0});
      expect(d.problems, contains(PlanProblem.badWeek));
    });

    test('a weekday that is not a weekday is dropped', () {
      final d = run(twoDayPlan({'monday': 0, '9': 1, '2': 1}));
      expect(d.week, {'2': 1});
      expect(d.problems, contains(PlanProblem.badWeek));
    });

    test('indices point at what survived, not at what was sent', () {
      // The subtle one. If a routine is dropped for holding only invented ids, every index after
      // it shifts — a week map validated against the original count would silently schedule the
      // wrong session.
      final d = run({
        'routines': [
          {
            'name': 'Ghost',
            'exercises': [ex('invented')]
          },
          {
            'name': 'Real',
            'exercises': [ex(curl)]
          },
        ],
        'week': {'1': 1},
      });
      expect(d.routines, hasLength(1));
      expect(d.routines.single.name, 'Real');
      // Index 1 no longer exists, so it is dropped rather than pointing at the wrong routine.
      expect(d.week, isEmpty);
      expect(d.problems, contains(PlanProblem.badWeek));
    });
  });

  group('text', () {
    test('a routine with no usable name still gets one', () {
      final d = run({
        'routines': [
          {
            'exercises': [ex(curl)]
          }
        ],
      });
      expect(d.routines.single.name, isNotEmpty);
    });

    test('an essay where a name belongs is cut to something a row can hold', () {
      final d = run(plan([ex(curl)], name: 'x' * 500));
      expect(d.routines.single.name.length, lessThanOrEqualTo(40));
    });

    test('a rationale is capped too', () {
      final d = run({
        ...plan([ex(curl)]),
        'rationale': 'y' * 2000,
      });
      expect(d.rationale!.length, lessThanOrEqualTo(400));
    });
  });
}
