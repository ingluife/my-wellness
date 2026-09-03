import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/day_plan.dart';
import 'package:my_wellness/domain/foods.dart';
import 'package:my_wellness/domain/format.dart';
import 'package:my_wellness/domain/nutrition.dart';

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

  /// Runs [check] over a plan for every body weight, goal and seed worth trying.
  ///
  /// The sizing faults this file guards against were all corner cases of one profile or one
  /// seed — 240 g of Brie needed a heavy user on a cut, 300 g of Feta needed seed 1 — so a
  /// single default profile is exactly the thing that would miss the next one.
  void forEveryPlan(void Function(String label, List<PlannedMeal> plan) check) {
    for (final w in [55.0, 80.0, 95.0, 120.0]) {
      for (final mode in ['cut', 'maintain', 'gain']) {
        final s = profiled(mode: mode, weight: w);
        for (var seed = 0; seed < 4; seed++) {
          check('$mode ${w.round()}kg seed $seed', buildDayPlan(s, todayISO(), seed: seed));
        }
      }
    }
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
      forEveryPlan((label, plan) {
        for (final m in plan) {
          for (final i in m.items) {
            final why = '$label ${m.name}: ${foods.or(i.fid!).n}';
            // A weight below this is not a portion, it is a rounding artefact.
            expect(i.g, greaterThanOrEqualTo(5), reason: why);
            expect(i.g, lessThanOrEqualTo(350), reason: why);
          }
        }
      });
    });

    test('sizes a rich food like a rich food', () {
      // The bug this whole sizing pass exists for. The anchor used to be sized to carry its
      // slot's entire protein share, which asked for 173 g of Brie — and `_snap` then rounded
      // that *up* onto `cup, melted = 240 g`, or 288 g at 120 kg on a cut. A cheese, an oil or a
      // nut is something you have a piece of; nothing at this density is ever eaten by the plate.
      forEveryPlan((label, plan) {
        for (final m in plan) {
          for (final i in m.items) {
            final food = foods.or(i.fid!);
            if (food.kcal < 300) continue;
            expect(i.g, lessThanOrEqualTo(80),
                reason: '$label ${m.name}: ${i.g.round()} g of ${food.n} at ${food.kcal} kcal');
          }
        }
      });
    });

    test('no single food is the whole meal', () {
      // The same fault seen from the other side: at seed 1 breakfast came out as 300 g of Feta
      // and nothing else, 795 kcal of cheese. A meal is several things, and the share caps are
      // what make that true rather than a coincidence of the catalogue.
      forEveryPlan((label, plan) {
        for (final m in plan) {
          // Not skipped when there is only one item: one item *is* the failure. Seed 1's
          // breakfast was a single 300 g block of Feta, and a test that steps over meals of one
          // thing would have watched it go by.
          expect(m.items.length, greaterThanOrEqualTo(2), reason: '$label ${m.name}');
          for (final i in m.items) {
            expect(i.kcal, lessThan(m.macros.kcal * 0.75),
                reason: '$label ${m.name}: ${foods.or(i.fid!).n} is most of the meal');
          }
        }
      });
    });

    test('offers a drink with breakfast, and never one to avoid', () {
      // The `drink` category was unreachable from the planner: eleven foods, coffee and tea
      // among them, that it could never propose — so a plan could not contain the one thing
      // almost every breakfast contains. Letting them in means ruling out the ones that are a
      // decision rather than a drink, or the afternoon snack arrives with a beer in it.
      final s = profiled();
      var breakfastsWithADrink = 0;
      for (var seed = 0; seed < 6; seed++) {
        for (final m in buildDayPlan(s, todayISO(), seed: seed)) {
          final drinks = m.items.where((i) => foods.or(i.fid!).cat == 'drink');
          if (m.name == 'Breakfast' && drinks.isNotEmpty) breakfastsWithADrink++;
          for (final d in drinks) {
            expect(foods.or(d.fid!).kcal, lessThanOrEqualTo(35),
                reason: 'seed $seed ${m.name}: ${foods.or(d.fid!).n}');
          }
        }
      }
      expect(breakfastsWithADrink, 6);
    });
  });

  group('the meals you already eat', () {
    MealItem it(String fid, double g) => foods.or(fid).portion(g);

    /// White bread, ham, cheddar, tomato, olive oil, coffee — a sandwich and a coffee.
    MealTemplate sandwich({String? slot = 'Breakfast', String n = 'Sandwich and coffee'}) =>
        MealTemplate(id: 'mt-$n', n: n, slot: slot, items: [
          it('f0114', 58),
          it('f0029', 50),
          it('f0067', 25),
          it('f0154', 40),
          it('f0221', 237),
        ]);

    test('a saved recipe is what breakfast becomes', () {
      // The complaint this whole change answers: "I normally eat a sandwich with coffee for
      // breakfast", against a planner that proposed 240 g of Brie because the arithmetic
      // allowed it. The user has written the answer down; it only had to be asked.
      final s = profiled();
      s.nutrition.templates.add(sandwich());

      final plan = buildDayPlan(s, todayISO());
      final breakfast = plan.firstWhere((m) => m.name == 'Breakfast');
      expect(breakfast.dish, 'Sandwich and coffee');
      expect([for (final i in breakfast.items) i.fid], contains('f0221'));
      expect([for (final i in breakfast.items) i.fid], contains('f0114'));
    });

    test('it is resized to the slot without ceasing to be itself', () {
      final s = profiled();
      s.nutrition.templates.add(sandwich());
      final target = macroTargets(s)!;
      final share = mealSplit(s.nutrition.goal).first.$2;

      final breakfast = buildDayPlan(s, todayISO()).first;
      // Near the slot it was fitted to, and still made of the same things in the same order.
      expect(breakfast.macros.kcal, closeTo(target.kcal * share, target.kcal * share * 0.35));
      expect([for (final i in breakfast.items) i.fid],
          [for (final i in sandwich().items) i.fid]);
    });

    test('the coffee in it is poured, not scaled', () {
      // A drink is `fixed`: the meal grows around it. Scaling the cup with the sandwich would
      // propose half a litre of coffee to pay for a bigger breakfast.
      final s = profiled();
      s.nutrition.templates.add(sandwich());
      for (var seed = 0; seed < 4; seed++) {
        final breakfast = buildDayPlan(s, todayISO(), seed: seed).first;
        final coffee = breakfast.items.firstWhere((i) => i.fid == 'f0221');
        expect(coffee.g, 237, reason: 'seed $seed');
      }
    });

    test('bread lands on whole slices', () {
      // `unit` parts move in household measures. An earlier version matched 58 g against four
      // *very thin* slices and resized in fifteen-gram steps to 90 g — a weight that is not a
      // whole number of any slice of bread.
      final s = profiled();
      s.nutrition.templates.add(sandwich());
      final bread = foods.or('f0114');
      for (var seed = 0; seed < 4; seed++) {
        final item = buildDayPlan(s, todayISO(), seed: seed)
            .first
            .items
            .firstWhere((i) => i.fid == 'f0114');
        expect(bread.portions.any((p) => item.g % p.g == 0),
            isTrue, reason: 'seed $seed: ${item.g} g of bread');
      }
    });

    test('a dinner-sized recipe is never crushed into a snack', () {
      // What makes slot-appropriateness fall out of the scoring rather than needing a rule.
      final s = profiled();
      s.nutrition.goal.meals = 4;
      s.nutrition.templates.add(MealTemplate(
        id: 'mt1',
        n: 'Big dinner',
        // Filed under no slot, so only its size can keep it out of the wrong one.
        items: [it('f0006', 300), it('f0115', 300), it('f0202', 20)],
      ));

      for (var seed = 0; seed < 4; seed++) {
        for (final m in buildDayPlan(s, todayISO(), seed: seed)) {
          if (m.name == 'Snack') {
            expect(m.dish, isNot('Big dinner'), reason: 'seed $seed');
          }
        }
      }
    });

    test('the same recipe is not served twice in one day', () {
      final s = profiled();
      s.nutrition.templates.add(sandwich(slot: null));
      for (var seed = 0; seed < 4; seed++) {
        final dishes = [
          for (final m in buildDayPlan(s, todayISO(), seed: seed)) ?m.dish
        ];
        expect(dishes.toSet(), hasLength(dishes.length), reason: 'seed $seed');
      }
    });

    test('a meal logged the same way three times is offered back', () {
      // One step before the user has agreed to keep it. `repeatedMeals` already finds these;
      // until now they only nudged which raw ingredients got picked.
      final s = profiled();
      final morning = DateTime.now().copyWith(hour: 8).millisecondsSinceEpoch;
      for (var i = 0; i < 3; i++) {
        s.meals.add(Meal(
          id: 'm$i',
          d: todayISO(),
          t: morning,
          items: [it('f0102', 60), it('f0080', 200), it('f0161', 120)],
        ));
      }
      final breakfast = buildDayPlan(s, todayISO()).first;
      expect(breakfast.dish, isNotNull);
      expect([for (final i in breakfast.items) i.fid], contains('f0102'));
    });

    test('proposing one still changes nothing', () {
      final s = profiled();
      s.nutrition.templates.add(sandwich());
      final before = s.toJson().toString();
      buildDayPlan(s, todayISO(), seed: 1);
      buildDayPlan(s, todayISO(), seed: 4);
      expect(s.toJson().toString(), before);
    });

    test('the same seed still gives the same day', () {
      final s = profiled();
      s.nutrition.templates.add(sandwich());
      String shape(List<PlannedMeal> p) => p
          .map((m) => '${m.dish}:${m.items.map((i) => '${i.fid}@${i.g}').join(',')}')
          .join('|');
      expect(shape(buildDayPlan(s, todayISO(), seed: 3)),
          shape(buildDayPlan(s, todayISO(), seed: 3)));
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
