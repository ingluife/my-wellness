import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/history.dart';
import 'package:my_wellness/domain/plan_share.dart';
import 'package:my_wellness/domain/starter.dart';

import 'helpers.dart';

void main() {
  setUpAll(loadExercises);

  AppState withStarter() {
    final s = AppState.defaults();
    final r = starterRoutines();
    s.routines.addAll(r);
    s.week['1'] = r[0].id;
    s.week['3'] = r[1].id;
    s.week['5'] = r[2].id;
    // Things a plan file must never carry.
    s.workouts.add(Workout(id: 'w', d: '2026-08-20', start: 0, end: 0, name: 'Push Day'));
    s.bodyweight.add(BodyWeightEntry(d: '2026-08-20', w: 80));
    s.targetW = 77;
    return s;
  }

  test('a bundle carries the plan and nothing else', () {
    final bundle = buildPlanBundle(withStarter(), 'Luis’s plan');
    expect(bundle['opengym_plan'], 1);
    expect(bundle['name'], 'Luis’s plan');
    expect((bundle['routines'] as List), hasLength(3));
    expect((bundle['week'] as Map).keys, ['1', '3', '5']);
    // No workouts, no weigh-ins, no settings.
    expect(bundle.containsKey('workouts'), isFalse);
    expect(bundle.containsKey('bodyweight'), isFalse);
    expect(bundle.containsKey('targetW'), isFalse);
  });

  test('a flag that disagrees with the catalogue does travel', () {
    // A dip done with a belt is not bodyweight training any more, and the other end cannot
    // work that out on its own.
    final s = AppState.defaults()
      ..routines.add(Routine(id: 'r', name: 'Push', ex: [
        ExerciseConfig(id: '0251', sets: 3, reps: 8, weight: 10, mode: 'reps', bodyweight: false),
      ]));
    final bundle = parsePlan(jsonEncode(buildPlanBundle(s, '')));
    final target = AppState.defaults();
    mergePlan(target, bundle);
    expect(target.routines.single.ex.single.bodyweight, isFalse);
    expect(isBw(target.routines.single.ex.single), isFalse);
  });

  test('a round trip through the file preserves what a routine prescribes', () {
    final s = AppState.defaults()
      ..routines.add(Routine(id: 'r', name: 'Push Day', emoji: 'barbell', prog: 'greyskull', ex: [
        ExerciseConfig(id: '0025', sets: 4, reps: 8, weight: 60, mode: 'reps', inc: 2.5),
        // Already bodyweight in the catalogue, so the flag should not need to travel.
        ExerciseConfig(id: '0251', sets: 3, reps: 12, mode: 'reps', bodyweight: true, repsMax: 20),
        ExerciseConfig(id: '3298', sets: 3, sec: 45, mode: 'time'),
      ]));

    final bundle = parsePlan(jsonEncode(buildPlanBundle(s, '')));
    final target = AppState.defaults();
    mergePlan(target, bundle);

    final r = target.routines.single;
    expect(r.name, 'Push Day');
    expect(r.emoji, 'barbell');
    expect(r.prog, 'greyskull');
    expect(r.ex.map((e) => e.id), ['0025', '0251', '3298']);
    expect(r.ex[0].inc, 2.5);
    // The flag itself is omitted because it agrees with the catalogue — the other end derives
    // it, which is what keeps the file small and a barbell config byte-identical.
    expect(r.ex[1].bodyweight, isNull);
    expect(isBw(r.ex[1]), isTrue);
    expect(r.ex[1].repsMax, 20);
    // A timed hold must not arrive as 45 reps.
    expect(r.ex[2].mode, 'time');
    expect(r.ex[2].sec, 45);
  });

  test('routines arrive with fresh ids, so nothing you already have is overwritten', () {
    final mine = AppState.defaults()..routines.add(Routine(id: 'r', name: 'My Push'));
    final bundle = parsePlan(jsonEncode(buildPlanBundle(
      AppState.defaults()
        ..routines.add(Routine(id: 'r', name: 'Their Push', ex: [ExerciseConfig(id: '0025', sets: 3)])),
      '',
    )));
    mergePlan(mine, bundle);

    expect(mine.routines.map((r) => r.name), ['My Push', 'Their Push']);
    expect(mine.routines[1].id, isNot('r'));
  });

  test('the schedule is only taken when asked for, and then replaces the week', () {
    final source = AppState.defaults();
    final r = Routine(id: 'r', name: 'Push', ex: [ExerciseConfig(id: '0025', sets: 3)]);
    source.routines.add(r);
    source.week['1'] = 'r';
    final bundle = parsePlan(jsonEncode(buildPlanBundle(source, '')));

    final ignored = AppState.defaults()..week['2'] = 'existing';
    mergePlan(ignored, bundle);
    expect(ignored.week['2'], 'existing');
    expect(ignored.week['1'], isNull);

    final taken = AppState.defaults()..week['2'] = 'existing';
    mergePlan(taken, bundle, schedule: true);
    // A half-overwritten week would silently mix two plans, so the shared one replaces it.
    expect(taken.week['2'], isNull);
    expect(taken.week['1'], taken.routines.single.id);
  });

  test('a custom exercise travels with the plan, and is reused rather than duplicated', () {
    final source = AppState.defaults()
      ..customEx.add(CustomExercise(id: 'c1', n: 'Sled push', bp: 'upper legs'))
      ..routines.add(Routine(id: 'r', name: 'Legs', ex: [ExerciseConfig(id: 'c1', sets: 3)]));
    final bundle = parsePlan(jsonEncode(buildPlanBundle(source, '')));

    final fresh = AppState.defaults();
    mergePlan(fresh, bundle);
    expect(fresh.customEx, hasLength(1));
    expect(fresh.routines.single.ex.single.id, fresh.customEx.single.id);

    // Importing the same plan again matches on name + body part rather than adding a twin.
    final already = AppState.defaults()
      ..customEx.add(CustomExercise(id: 'mine', n: 'Sled push', bp: 'upper legs'));
    mergePlan(already, bundle);
    expect(already.customEx, hasLength(1));
    expect(already.routines.single.ex.single.id, 'mine');
  });

  test('an exercise nothing can resolve is dropped and counted, not left invisible', () {
    final bundle = parsePlan(jsonEncode({
      'opengym_plan': 1,
      'routines': [
        {
          'id': 'r',
          'name': 'Mixed',
          'ex': [
            {'id': '0025', 'sets': 3},
            {'id': 'nope-not-a-real-id', 'sets': 3},
          ]
        }
      ],
    }));
    expect(bundle.dropped, 1);
    expect(bundle.exerciseCount, 1);
  });

  test('anything that is not a plan file is refused with a readable message', () {
    expect(() => parsePlan('not json'), throwsA(isA<FormatException>()));
    expect(() => parsePlan('{"workouts":[]}'), throwsA(isA<FormatException>()));
    expect(() => parsePlan('{"opengym_plan":1}'), throwsA(isA<FormatException>()));
  });

  test('the bundle counts what it is about to add', () {
    final bundle = parsePlan(jsonEncode(buildPlanBundle(withStarter(), '')));
    expect(bundle.routineCount, 3);
    expect(bundle.exerciseCount, 17);
    expect(bundle.scheduledDays, 3);
  });
}
