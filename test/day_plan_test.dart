import 'package:flutter_test/flutter_test.dart';
import 'package:my_open_gym/data/models/app_state.dart';
import 'package:my_open_gym/domain/day_plan.dart';
import 'package:my_open_gym/domain/foods.dart';
import 'package:my_open_gym/domain/format.dart';
import 'package:my_open_gym/domain/nutrition.dart';

import 'helpers.dart';

void main() {
  setUpAll(() async {
    await loadExercises();
    await foods.load();
  });

  AppState profiled({String mode = 'maintain', double weight = 80}) {
    final s = AppState.defaults();
    s.nutrition.profile
      ..age = 34
      ..height = 178
      ..sex = 'male'
      ..activity = 'light';
    s.nutrition.goal.mode = mode;
    s.bodyweight.add(BodyWeightEntry(d: todayISO(), w: weight));
    return s;
  }

  test('a profile with no target gets no plan rather than a guess', () {
    expect(buildDayPlan(AppState.defaults(), todayISO()), isEmpty);
  });

  test('there is one meal per slot, and every meal has food in it', () {
    final s = profiled();
    final plan = buildDayPlan(s, todayISO());
    expect(plan, hasLength(mealSplit(s.nutrition.goal).length));
    for (final m in plan) {
      expect(m.items, isNotEmpty, reason: m.name);
      expect(m.macros.kcal, greaterThan(0), reason: m.name);
    }
  });

  group('it lands near the target', () {
    for (final mode in ['cut', 'maintain', 'gain']) {
      test('on a $mode', () {
        final s = profiled(mode: mode);
        final target = macroTargets(s)!;
        final got = dayPlanTotals(buildDayPlan(s, todayISO()));

        // Whole foods snapped to household portions cannot hit a number exactly, and pretending
        // otherwise would mean proposing 173 g of rice. Within a quarter is close enough to be
        // a useful example of a day.
        expect(got.kcal, closeTo(target.kcal, target.kcal * 0.25), reason: '$mode kcal');
        expect(got.p, greaterThan(target.p * 0.7), reason: '$mode protein');
      });
    }

    test('across a range of body weights', () {
      for (final w in [55.0, 70.0, 95.0, 120.0]) {
        final s = profiled(weight: w);
        final target = macroTargets(s)!;
        final got = dayPlanTotals(buildDayPlan(s, todayISO()));
        expect(got.kcal, closeTo(target.kcal, target.kcal * 0.3), reason: '$w kg');
      }
    });

    test('and across every meal count the plan offers', () {
      for (var n = 2; n <= 6; n++) {
        final s = profiled();
        s.nutrition.goal.meals = n.toDouble();
        final target = macroTargets(s)!;
        final plan = buildDayPlan(s, todayISO());
        expect(plan, hasLength(n));
        expect(dayPlanTotals(plan).kcal, closeTo(target.kcal, target.kcal * 0.3),
            reason: '$n meals');
      }
    });
  });

  group('determinism', () {
    test('the same seed gives the same day, twice', () {
      final s = profiled();
      String shape(List<PlannedMeal> p) =>
          p.map((m) => m.items.map((i) => '${i.fid}@${i.g}').join(',')).join('|');
      expect(shape(buildDayPlan(s, todayISO(), seed: 3)),
          shape(buildDayPlan(s, todayISO(), seed: 3)));
    });

    test('a different seed gives a different day', () {
      final s = profiled();
      String shape(List<PlannedMeal> p) =>
          p.map((m) => m.items.map((i) => i.fid).join(',')).join('|');
      final seen = {for (var i = 0; i < 5; i++) shape(buildDayPlan(s, todayISO(), seed: i))};
      // Not all five have to differ, but a shuffle that never changes anything is broken.
      expect(seen.length, greaterThan(1));
    });
  });

  group('the food it chooses', () {
    test('is not the same thing at every meal', () {
      final s = profiled();
      final plan = buildDayPlan(s, todayISO());
      final ids = [for (final m in plan) for (final i in m.items) i.fid];
      expect(ids.toSet().length, greaterThan(ids.length ~/ 2));
    });

    test('prefers what the user actually eats over the catalogue', () {
      final s = profiled();
      // Someone who logs tofu and lentils should not be handed a plan built on beef.
      final tofu = foods.db.firstWhere((f) => f.n == 'Tofu, firm');
      final lentils = foods.db.firstWhere((f) => f.n == 'Lentils');
      s.meals.add(Meal(id: 'm1', d: todayISO(), items: [
        tofu.portion(200),
        lentils.portion(200),
      ]));

      final ids = [
        for (final m in buildDayPlan(s, todayISO()))
          for (final i in m.items) i.fid
      ];
      expect(ids, anyOf(contains(tofu.id), contains(lentils.id)));
    });

    test('lands on household portions where it can', () {
      final s = profiled();
      var snapped = 0;
      var total = 0;
      for (final m in buildDayPlan(s, todayISO())) {
        for (final i in m.items) {
          total++;
          final food = foods.or(i.fid!);
          if (food.portions.any((p) => [1, 2, 3, 4].any((n) => p.g * n == i.g))) snapped++;
        }
      }
      // "1 chicken breast" beats "173 g" as an instruction, so most items should be a real
      // measure rather than an arithmetic result.
      expect(snapped / total, greaterThan(0.4));
    });

    test('never proposes an absurd amount of anything', () {
      for (final w in [55.0, 120.0]) {
        for (final mode in ['cut', 'gain']) {
          final s = profiled(mode: mode, weight: w);
          for (final m in buildDayPlan(s, todayISO())) {
            for (final i in m.items) {
              expect(i.g, greaterThanOrEqualTo(30), reason: '$mode $w: ${i.fid}');
              expect(i.g, lessThanOrEqualTo(350), reason: '$mode $w: ${i.fid}');
            }
          }
        }
      }
    });
  });

  test('generating a plan changes nothing', () {
    // The property the whole design turns on: a plan is an intention, and evolution() must
    // never see a meal nobody ate.
    final s = profiled();
    final before = s.toJson().toString();
    buildDayPlan(s, todayISO(), seed: 2);
    buildDayPlan(s, todayISO(), seed: 9);
    expect(s.meals, isEmpty);
    expect(s.toJson().toString(), before);
  });
}
