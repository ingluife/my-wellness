import 'package:flutter_test/flutter_test.dart';
import 'package:my_open_gym/data/models/app_state.dart';
import 'package:my_open_gym/domain/coaching.dart';
import 'package:my_open_gym/domain/foods.dart';
import 'package:my_open_gym/domain/format.dart';
import 'package:my_open_gym/domain/nutrition.dart';

import 'helpers.dart';

/// The advice layer. These tests pin the *judgement*, not the arithmetic: which single thing
/// the app decides to say, and — more importantly — when it decides to say nothing at all.
void main() {
  setUpAll(() async {
    await loadExercises();
    await foods.load();
  });

  String daysAgo(int n) {
    final d = DateTime.now();
    return isoOf(DateTime(d.year, d.month, d.day - n, 12));
  }

  AppState profiled({double weight = 80}) {
    final s = AppState.defaults();
    s.nutrition.profile
      ..age = 34
      ..height = 178
      ..sex = 'male'
      ..activity = 'light';
    s.bodyweight.add(BodyWeightEntry(d: daysAgo(0), w: weight));
    return s;
  }

  Meal meal(String d, {double kcal = 0, double p = 0}) => Meal(
        id: 'm-$d-$kcal',
        d: d,
        items: [MealItem(g: 100, kcal: kcal, p: p, c: 0, f: 0)],
      );

  group('the breakdown', () {
    test('says nothing when there is nothing to explain', () {
      expect(targetBreakdown(AppState.defaults()), isEmpty);
    });

    test('walks from resting rate to the number on screen', () {
      final s = profiled();
      final steps = targetBreakdown(s);
      final labels = steps.map((x) => x.label);

      expect(labels, contains('Resting'));
      expect(labels, contains('Daily activity'));
      expect(labels, contains('Maintenance'));

      // The resting line must be the actual BMR, not a re-derivation that could drift.
      expect(steps.first.value, closeTo(bmr(s)!, 1e-9));
    });

    test('maintenance is resting plus activity plus training', () {
      final s = profiled();
      final steps = targetBreakdown(s);
      final by = {for (final x in steps) x.label: x.value};
      expect(by['Maintenance'],
          closeTo(by['Resting']! + by['Daily activity']!, 1e-6));
    });

    test('the steps add up to the target that is actually shown', () {
      final s = profiled();
      s.nutrition.goal.mode = 'cut';
      final steps = targetBreakdown(s);
      final total = steps
          .where((x) => x.label != 'Maintenance')
          .fold(0.0, (a, x) => a + x.value);
      expect(total, closeTo(macroTargets(s)!.kcal, 1e-6));
    });

    test('a floored goal says so, in its own line', () {
      final s = profiled();
      s.nutrition.goal
        ..mode = 'cut'
        ..rate = -3;
      expect(targetBreakdown(s).map((x) => x.label), contains('Held at the floor'));
    });

    test('a hand-set number replaces the goal arithmetic rather than joining it', () {
      final s = profiled();
      s.nutrition.goal
        ..mode = 'cut'
        ..kcal = 2000;
      final labels = targetBreakdown(s).map((x) => x.label);
      expect(labels, contains('Your own number'));
      expect(labels, isNot(contains('Held at the floor')));
    });
  });

  group('swaps', () {
    test('offer more protein for the same calories, in the same aisle', () {
      final s = AppState.defaults();
      final peanut = foods.db.firstWhere((f) => f.n == 'Peanut butter');
      for (final swap in swapsFor(s, peanut)) {
        expect(swap.cat, peanut.cat);
        expect(swap.proteinDensity, greaterThan(peanut.proteinDensity));
        expect((swap.kcal - peanut.kcal).abs(), lessThanOrEqualTo(peanut.kcal * 0.34));
      }
    });

    test('nothing is suggested for a food that is already the best of its kind', () {
      final s = AppState.defaults();
      final white = foods.db.firstWhere((f) => f.n == 'Egg white');
      // Near-pure protein: there is nothing in its category to trade up to.
      expect(swapsFor(s, white), isEmpty);
    });

    test('a food never suggests itself, and zero-calorie foods suggest nothing', () {
      final s = AppState.defaults();
      final chicken = foods.db.firstWhere((f) => f.n == 'Chicken breast');
      expect(swapsFor(s, chicken).map((f) => f.id), isNot(contains(chicken.id)));

      const empty = Food(id: 'x', n: 'water', cat: 'drink', kcal: 0, p: 0, c: 0, f: 0);
      expect(swapsFor(s, empty), isEmpty);
    });
  });

  group('the focus ladder', () {
    /// [days] logged days in the window, each hitting [p] g of protein and [kcal] calories.
    AppState logging({required int days, required double kcal, required double p}) {
      final s = profiled();
      for (var i = 0; i < days; i++) {
        s.meals.add(meal(daysAgo(i), kcal: kcal, p: p));
      }
      return s;
    }

    test('with almost no history, the only thing to work on is logging', () {
      expect(focusOf(profiled()).what, NutritionFocus.logConsistently);
      expect(focusOf(logging(days: 3, kcal: 2000, p: 160)).what,
          NutritionFocus.logConsistently);
    });

    test('seven logged days is where it starts judging anything else', () {
      final s = logging(days: 7, kcal: 2200, p: 160);
      expect(focusOf(s).what, isNot(NutritionFocus.logConsistently));
      expect(focusOf(s).loggedDays, 7);
    });

    test('protein comes before calories', () {
      // Calories bang on target, protein nowhere near it: protein is the thing to say.
      final s = logging(days: 10, kcal: 2272, p: 40);
      final f = focusOf(s);
      expect(f.what, NutritionFocus.hitProtein);
      expect(f.proteinRate, lessThan(0.8));
    });

    test('with protein handled, calories become the thing', () {
      final s = logging(days: 10, kcal: 3500, p: 200);
      final f = focusOf(s);
      expect(f.what, NutritionFocus.hitCalories);
      expect(f.proteinRate, greaterThanOrEqualTo(0.8));
    });

    test('someone doing both well is told to refine, not nagged', () {
      final s = logging(days: 12, kcal: 2272, p: 200);
      expect(focusOf(s).what, NutritionFocus.refine);
    });

    test('days outside the window do not count', () {
      final s = profiled();
      for (var i = 20; i < 32; i++) {
        s.meals.add(meal(daysAgo(i), kcal: 2200, p: 160));
      }
      expect(focusOf(s).what, NutritionFocus.logConsistently);
      expect(focusOf(s).loggedDays, 0);
    });
  });

  group('the suggested adjustment', () {
    /// A profile that logged [kcal] a day for [days] and moved from 80 kg to [endWeight].
    AppState tracked({int days = 30, double kcal = 1500, required double endWeight}) {
      final s = profiled();
      s.nutrition.goal.mode = 'cut';
      for (var i = days; i >= 0; i--) {
        s.meals.add(meal(daysAgo(i), kcal: kcal, p: 150));
      }
      s.bodyweight
        ..clear()
        ..add(BodyWeightEntry(d: daysAgo(days), w: 80))
        ..add(BodyWeightEntry(d: daysAgo(0), w: endWeight));
      return s;
    }

    test('says nothing without enough evidence to be worth acting on', () {
      expect(suggestedAdjustment(AppState.defaults()), isNull);
      // A fortnight is the floor; a five-day window is noise.
      expect(suggestedAdjustment(tracked(days: 5, endWeight: 79.9)), isNull);
    });

    test('says nothing when the log and the scale agree', () {
      final s = tracked(endWeight: 77);
      final ev = evolution(s)!;
      expect(ev.gap.abs(), lessThan(0.5));
      expect(suggestedAdjustment(s), isNull);
    });

    test('a scale above the prediction asks for a smaller target', () {
      final s = tracked(endWeight: 79.5);
      final a = suggestedAdjustment(s)!;
      expect(a.delta, lessThan(0));
      expect(a.kcal, lessThan(macroTargets(s)!.kcal));
      expect(a.reason, contains('above'));
    });

    test('a scale below the prediction offers more food', () {
      final s = tracked(kcal: 2400, endWeight: 73);
      final a = suggestedAdjustment(s);
      expect(a, isNotNull);
      expect(a!.delta, greaterThan(0));
      expect(a.kcal, greaterThan(macroTargets(s)!.kcal));
    });

    test('turning it down stops it asking again', () {
      final s = tracked(endWeight: 79.5);
      expect(suggestedAdjustment(s), isNotNull);

      s.nutrition.dismissedAdj = DateTime.now().millisecondsSinceEpoch;
      expect(suggestedAdjustment(s), isNull);

      // ...but not forever. Two weeks on, the question is fair again.
      s.nutrition.dismissedAdj =
          DateTime.now().subtract(const Duration(days: 15)).millisecondsSinceEpoch;
      expect(suggestedAdjustment(s), isNotNull);
    });

    test('it only ever proposes — nothing is applied', () {
      final s = tracked(endWeight: 79.5);
      final before = macroTargets(s)!.kcal;
      suggestedAdjustment(s);
      expect(macroTargets(s)!.kcal, before);
      expect(s.nutrition.goal.kcal, isNull);
    });
  });
}
