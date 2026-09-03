import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/format.dart';
import 'package:my_wellness/domain/nutrition.dart';

import 'helpers.dart';

void main() {
  setUpAll(loadExercises);

  String daysAgo(int n) {
    final d = DateTime.now();
    return isoOf(DateTime(d.year, d.month, d.day - n, 12));
  }

  /// A profile complete enough to estimate from: 34, 178 cm, male, 80 kg.
  AppState profiled({String unit = 'kg', double weight = 80}) {
    final s = AppState.defaults();
    s.unit = unit;
    s.nutrition.profile
      ..age = 34
      ..height = 178
      ..sex = 'male'
      ..activity = 'light';
    s.bodyweight.add(BodyWeightEntry(d: daysAgo(0), w: weight));
    return s;
  }

  Meal meal(String d, List<MealItem> items) => Meal(id: 'm-$d', d: d, items: items);

  MealItem item({double kcal = 0, double p = 0, double c = 0, double f = 0}) =>
      MealItem(g: 100, kcal: kcal, p: p, c: c, f: f);

  group('units', () {
    test('a pound profile is converted, because the state never converts it', () {
      // AppState.unit is a label only: an lb profile stores pounds in `w`. A formula that read
      // it as kg would compute a BMR for a 176 kg man and be ~800 kcal out.
      expect(kgOf(176, 'lb'), closeTo(79.83, 0.01));
      expect(kgOf(80, 'kg'), 80);
      expect(bodyKg(profiled(unit: 'lb', weight: 176)), closeTo(79.83, 0.01));
      expect(bodyKg(profiled(weight: 80)), 80);
    });

    test('with no weigh-in there is no estimate at all', () {
      final s = AppState.defaults();
      s.nutrition.profile
        ..age = 34
        ..height = 178
        ..sex = 'male';
      expect(bodyKg(s), isNull);
      expect(bmr(s), isNull);
      expect(macroTargets(s), isNull);
    });
  });

  group('bmr', () {
    test('matches Mifflin-St Jeor for both sexes', () {
      // 10(80) + 6.25(178) - 5(34) + 5 = 1747.5
      final m = BodyProfile(age: 34, height: 178, sex: 'male');
      expect(bmrOf(m, 80), closeTo(1747.5, 1e-9));
      // ...and the same body, female: -161 instead of +5 = 1581.5
      final f = BodyProfile(age: 34, height: 178, sex: 'female');
      expect(bmrOf(f, 80), closeTo(1581.5, 1e-9));
    });

    test('an incomplete profile estimates nothing rather than guessing', () {
      expect(bmrOf(BodyProfile(age: 34, height: 178), 80), isNull);
      expect(bmrOf(BodyProfile(age: 34, sex: 'male'), 80), isNull);
      expect(bmrOf(BodyProfile(height: 178, sex: 'male'), 80), isNull);
      expect(bmrOf(BodyProfile(age: 34, height: 178, sex: 'male'), 0), isNull);
    });
  });

  group('workout burn', () {
    test('is charged over resting, not on top of it', () {
      // One hour at 4.5 MET for 80 kg = (4.5 - 1) x 80 x 1 = 280 kcal.
      final w = Workout(
        id: 'w1',
        d: daysAgo(0),
        start: 0,
        end: 3600000,
        name: '',
        entries: [
          WorkoutEntry(id: '0025', sets: [SetLog(w: 60, r: 8, done: true)]),
        ],
      );
      expect(workoutBurn(w, 80), closeTo(280, 1e-6));
    });

    test('history imported with no clock falls back to a per-set estimate', () {
      // start == end == 0 is what every CSV import looks like.
      final w = wk(daysAgo(1), [
        WorkoutEntry(id: '0025', sets: [
          for (var i = 0; i < 20; i++) SetLog(w: 60, r: 8, done: true),
        ]),
      ]);
      expect(sessionMinutes(w), 60);
      expect(workoutBurn(w, 80), closeTo(280, 1e-6));
    });

    test('cardio is costed from its own minutes', () {
      final w = Workout(
        id: 'w1',
        d: daysAgo(0),
        start: 0,
        end: 1800000, // 30 min wall clock, all of it the run
        name: '',
        entries: [
          WorkoutEntry(
            id: '0025',
            target: ExerciseConfig(id: '0025', mode: 'cardio'),
            sets: [SetLog(min: 30, speed: 12, done: true)],
          ),
        ],
      );
      // 11.74 MET at 12 km/h: (11.74 - 1) x 80 x 0.5 ~= 430 kcal.
      expect(workoutBurn(w, 30 / 60 * 0 + 80), closeTo(429.6, 1));
    });

    test('a weightless profile burns nothing rather than dividing by it', () {
      expect(workoutBurn(wk(daysAgo(0), []), 0), 0);
    });
  });

  group('planned burn', () {
    test('a routine costs something before it has ever been done', () {
      final s = profiled();
      final r = Routine(id: 'r1', name: 'Push', ex: [
        ExerciseConfig(id: '0025', sets: 4, reps: 8),
        ExerciseConfig(id: '0031', sets: 3, reps: 10),
      ]);
      s.routines.add(r);
      s.week['1'] = 'r1'; // Monday

      expect(burnOfRoutine(s, r), greaterThan(0));
      // 7 planned sets at (45s work + 90s rest) = ~15.75 min at 4.5 MET.
      expect(plannedMinutes(s, r), closeTo(15.75, 0.01));
      expect(plannedWeeklyBurn(s), closeTo(burnOfRoutine(s, r), 1e-9));
    });

    test('a rest day costs nothing', () {
      final s = profiled();
      s.dayPlan[daysAgo(0)] = 'rest';
      expect(plannedBurn(s, daysAgo(0)), 0);
    });

    test('a longer rest interval means a longer session', () {
      final s = profiled();
      final r = Routine(id: 'r1', name: 'Push', ex: [ExerciseConfig(id: '0025', sets: 4)]);
      final short = plannedMinutes(s, r);
      s.restSec = 180;
      expect(plannedMinutes(s, r), greaterThan(short));
    });
  });

  group('tdee', () {
    test('adds training on top of a non-exercise activity factor', () {
      final s = profiled();
      // No history and no plan: 1747.5 x 1.3 = 2271.75, nothing trained.
      expect(trainingBurn(s), 0);
      expect(tdee(s), closeTo(1747.5 * 1.3, 1e-6));
    });

    test('falls back to the plan until there is history to read', () {
      final s = profiled();
      final r = Routine(id: 'r1', name: 'Push', ex: [ExerciseConfig(id: '0025', sets: 10)]);
      s.routines.add(r);
      s.week['1'] = 'r1';
      s.week['4'] = 'r1';
      // Two planned sessions a week, spread across seven days.
      expect(trainingBurn(s), closeTo(burnOfRoutine(s, r) * 2 / 7, 1e-6));
    });

    test('prefers what was actually logged once there is any', () {
      final s = profiled();
      final r = Routine(id: 'r1', name: 'Push', ex: [ExerciseConfig(id: '0025', sets: 10)]);
      s.routines.add(r);
      s.week['1'] = 'r1';
      s.workouts.add(Workout(
        id: 'w1',
        d: daysAgo(1),
        start: 0,
        end: 3600000,
        name: '',
        entries: [
          WorkoutEntry(id: '0025', sets: [SetLog(w: 60, r: 8, done: true)]),
        ],
      ));
      // One 280 kcal session spread over the 7-day window.
      expect(trainingBurn(s), closeTo(280 / 7, 1e-6));
    });
  });

  group('macro targets', () {
    test('a cut sits below maintenance and a gain above it', () {
      final s = profiled();
      final maintain = macroTargets(s)!.kcal;

      s.nutrition.goal.mode = 'cut';
      final cut = macroTargets(s)!.kcal;
      s.nutrition.goal.mode = 'gain';
      final gain = macroTargets(s)!.kcal;

      expect(cut, lessThan(maintain));
      expect(gain, greaterThan(maintain));
      // +0.25 kg/week is 7700 x 0.25 / 7 = 275 kcal a day, and a surplus never hits a floor.
      expect(gain - maintain, closeTo(275, 1e-6));
    });

    test('a sedentary cut is held back by the floor rather than served in full', () {
      // 80 kg, no training: maintenance is 2272 and the full -550 would land at 1722, under
      // this profile's own resting metabolism. The deficit is capped and says so.
      final s = profiled();
      s.nutrition.goal.mode = 'cut';
      expect(targetFloored(s), isTrue);
      expect(macroTargets(s)!.kcal, closeTo(bmr(s)! * 1.1, 1e-6));
      // The rate the user actually gets is smaller than the one they asked for.
      expect(achievableRate(s), greaterThan(goalRate(s.nutrition.goal)));
      expect(achievableRate(s), lessThan(0));
    });

    test('training earns back the room for the full deficit', () {
      final s = profiled();
      s.nutrition.goal.mode = 'cut';
      // Five hard hours a week lifts maintenance clear of the floor.
      for (var i = 1; i <= 5; i++) {
        s.workouts.add(Workout(
          id: 'w$i',
          d: daysAgo(i),
          start: 0,
          end: 3600000,
          name: '',
          entries: [
            WorkoutEntry(id: '0025', sets: [SetLog(w: 60, r: 8, done: true, rir: 0)]),
          ],
        ));
      }
      expect(targetFloored(s), isFalse);
      final full = tdee(s)! - macroTargets(s)!.kcal;
      expect(full, closeTo(550, 1e-6));
      expect(achievableRate(s), closeTo(-0.5, 1e-9));
    });

    test('macros add back up to the calorie target', () {
      for (final mode in ['cut', 'maintain', 'gain']) {
        final s = profiled();
        s.nutrition.goal.mode = mode;
        final m = macroTargets(s)!;
        expect(m.p * 4 + m.c * 4 + m.f * 9, closeTo(m.kcal, 1e-6), reason: mode);
      }
    });

    test('protein is highest on a cut, where lean mass is at risk', () {
      final s = profiled();
      s.nutrition.goal.mode = 'cut';
      final cut = macroTargets(s)!.p;
      s.nutrition.goal.mode = 'maintain';
      expect(cut, greaterThan(macroTargets(s)!.p));
      expect(cut, closeTo(2.0 * 80, 1e-6));
    });

    test('no goal can prescribe eating below resting metabolism', () {
      final s = profiled();
      // 3 kg a week is 3,300 kcal a day off — far past maintenance.
      s.nutrition.goal
        ..mode = 'cut'
        ..rate = -3;
      final m = macroTargets(s)!;
      expect(m.kcal, closeTo(bmr(s)! * 1.1, 1e-6));
      // ...and the macros still add up at the floor rather than going negative.
      expect(m.c, greaterThanOrEqualTo(0));
      expect(m.p * 4 + m.c * 4 + m.f * 9, closeTo(m.kcal, 1e-6));
    });

    test('an explicit override wins over the computed number', () {
      final s = profiled();
      s.nutrition.goal
        ..kcal = 2500
        ..protein = 200
        ..fatPct = 30;
      final m = macroTargets(s)!;
      expect(m.kcal, 2500);
      expect(m.p, 200);
      expect(m.f, closeTo(2500 * 0.3 / 9, 1e-6));
    });

    test('fat has a floor as well as a share', () {
      final s = profiled();
      s.nutrition.goal
        ..mode = 'cut'
        ..fatPct = 5; // well under what 0.6 g/kg needs
      expect(macroTargets(s)!.f, greaterThanOrEqualTo(0.6 * 80));
    });

    test('a training day is given more than a rest day', () {
      final s = profiled();
      final r = Routine(id: 'r1', name: 'Push', ex: [ExerciseConfig(id: '0025', sets: 10)]);
      s.routines.add(r);
      final train = daysAgo(0);
      final rest = daysAgo(1);
      s.dayPlan[train] = 'r1';
      s.dayPlan[rest] = 'rest';
      expect(macroTargets(s, iso: train)!.kcal,
          greaterThan(macroTargets(s, iso: rest)!.kcal));
    });
  });

  group('the log', () {
    test('totals a day from what was logged, not from the catalog', () {
      final s = profiled();
      final today = daysAgo(0);
      s.meals
        ..add(meal(today, [item(kcal: 216, p: 40.5), item(kcal: 120, p: 6.4, c: 9.1, f: 6.2)]))
        ..add(meal(today, [item(kcal: 325, p: 6.8, c: 70.5, f: 1.2)]))
        ..add(meal(daysAgo(1), [item(kcal: 999)]));

      final d = dayTotals(s, today);
      expect(d.kcal, closeTo(661, 1e-9));
      expect(d.p, closeTo(53.7, 1e-9));
      expect(d.c, closeTo(79.6, 1e-9));
      expect(d.f, closeTo(7.4, 1e-9));
      expect(mealsOn(s, today), hasLength(2));
    });

    test('an empty day is zero, not null', () {
      expect(dayTotals(profiled(), daysAgo(3)).kcal, 0);
    });

    test('a week buckets with the same weekKey the rest of the app uses', () {
      final s = profiled();
      final today = daysAgo(0);
      s.meals.add(meal(today, [item(kcal: 500)]));
      expect(weekTotals(s, today).kcal, 500);
      expect(weekDays(today), hasLength(7));
      expect(weekDays(today), contains(today));
    });
  });

  group('evolution', () {
    /// A profile that logged [kcal] every day for [days] and weighed in at both ends.
    AppState logged({required int days, required double kcal, required double endWeight}) {
      final s = profiled();
      s.nutrition.goal.mode = 'cut';
      for (var i = days; i >= 0; i--) {
        s.meals.add(meal(daysAgo(i), [item(kcal: kcal, p: 150, c: 200, f: 60)]));
      }
      s.bodyweight
        ..clear()
        ..add(BodyWeightEntry(d: daysAgo(days), w: 80))
        ..add(BodyWeightEntry(d: daysAgo(0), w: endWeight));
      return s;
    }

    test('says nothing when there is nothing to compare', () {
      expect(evolution(AppState.defaults()), isNull);
      // One weigh-in is a point, not a trend.
      final s = profiled();
      s.meals.add(meal(daysAgo(0), [item(kcal: 2000)]));
      expect(evolution(s), isNull);
    });

    test('a deficit predicts a loss', () {
      final s = logged(days: 30, kcal: 1500, endWeight: 77);
      final e = evolution(s)!;
      expect(e.dailyBalance, lessThan(0));
      expect(e.predicted, lessThan(0));
      expect(e.observed, closeTo(-3, 1e-9));
      expect(e.loggedDays, 31);
    });

    test('the gap is what the scale did minus what the log implied', () {
      final s = logged(days: 30, kcal: 1500, endWeight: 77);
      final e = evolution(s)!;
      expect(e.gap, closeTo(e.observed - e.predicted, 1e-9));
    });

    test('under-logging shows up as the scale falling short of the prediction', () {
      // Same logged intake, but the scale barely moved: the numbers are flattering this user.
      final honest = evolution(logged(days: 30, kcal: 1500, endWeight: 77))!;
      final flattered = evolution(logged(days: 30, kcal: 1500, endWeight: 79.5))!;

      // Both predict a similar loss — not an identical one, because a heavier body really does
      // spend more and every day is costed at the current weight.
      expect(flattered.predicted, closeTo(honest.predicted, 0.3));
      expect(honest.predicted, lessThan(0));

      // The signal that matters: the same log against a scale that moved less leaves a larger
      // gap, which is the app saying "these numbers are optimistic for you".
      expect(flattered.gap, greaterThan(honest.gap));
      expect(flattered.gap, greaterThan(1));
    });

    test('a fortnight is the floor for calling it reliable', () {
      expect(evolution(logged(days: 30, kcal: 1500, endWeight: 77))!.reliable, isTrue);
      expect(evolution(logged(days: 5, kcal: 1500, endWeight: 79))!.reliable, isFalse);
    });

    test('days with nothing logged are not counted as fasting', () {
      final s = profiled();
      s.bodyweight
        ..clear()
        ..add(BodyWeightEntry(d: daysAgo(30), w: 80))
        ..add(BodyWeightEntry(d: daysAgo(0), w: 79));
      // Two logged days out of thirty. The balance must come from those two, not from 28 days
      // of assumed zero intake, which would predict losing eight kilos.
      s.meals
        ..add(meal(daysAgo(10), [item(kcal: 2000)]))
        ..add(meal(daysAgo(9), [item(kcal: 2000)]));
      final e = evolution(s)!;
      expect(e.loggedDays, 2);
      expect(e.predicted.abs(), lessThan(0.5));
      expect(e.reliable, isFalse);
    });
  });

  group('the weekly budget', () {
    test('sums each day\'s own target, so training days are priced in', () {
      final s = profiled();
      final r = Routine(id: 'r1', name: 'Push', ex: [ExerciseConfig(id: '0025', sets: 10)]);
      s.routines.add(r);
      final flat = weekBudget(s, todayISO()).budget;

      // Three training days a week has to be worth more than none.
      for (final d in ['1', '3', '5']) {
        s.week[d] = 'r1';
      }
      expect(weekBudget(s, todayISO()).budget, greaterThan(flat));
    });

    test('spends only days that have happened', () {
      final s = profiled();
      final week = weekDays(todayISO());
      final future = week.where((d) => d.compareTo(todayISO()) > 0).toList();
      if (future.isEmpty) return; // Sunday: nothing to assert.

      s.meals.add(meal(future.first, [item(kcal: 900)]));
      // Something logged against Friday on a Tuesday is not money already spent.
      expect(weekBudget(s, todayISO()).spent, 0);
    });

    test('today still counts as a day you can spend', () {
      final s = profiled();
      final b = weekBudget(s, todayISO());
      expect(b.daysLeft, greaterThanOrEqualTo(1));
      expect(b.perDayLeft, closeTo(b.left / b.daysLeft, 1e-9));
    });

    test('what is left is the budget less what has gone', () {
      final s = profiled();
      s.meals.add(meal(todayISO(), [item(kcal: 800, p: 60, c: 80, f: 25)]));
      final b = weekBudget(s, todayISO());
      expect(b.spent, 800);
      expect(b.left, closeTo(b.budget - 800, 1e-9));
    });

    test('a week is seven days of the daily target when nothing is trained', () {
      final s = profiled();
      final daily = macroTargets(s, iso: todayISO())!.kcal;
      expect(weekBudget(s, todayISO()).budget, closeTo(daily * 7, 1));
    });
  });

  group('saved meals', () {
    MealItem it(String fid, double g) =>
        MealItem(fid: fid, g: g, kcal: g, p: g / 5, c: 0, f: 0);

    test('the same meal logged twice has the same signature', () {
      final a = [it('f0010', 200), it('f0107', 150)];
      final b = [it('f0010', 200), it('f0107', 150)];
      expect(signatureOf(a), signatureOf(b));
    });

    test('order does not make it a different meal', () {
      expect(signatureOf([it('f0010', 200), it('f0107', 150)]),
          signatureOf([it('f0107', 150), it('f0010', 200)]));
    });

    test('grams are rounded, so weighing imprecisely is still the same meal', () {
      // 148 g and 150 g of chicken is the same breakfast. Nobody weighs to the gram, and
      // treating them as distinct would mean the repeat offer never fires.
      expect(signatureOf([it('f0010', 148)]), signatureOf([it('f0010', 150)]));
      // ...but a genuinely different portion is a different meal.
      expect(signatureOf([it('f0010', 100)]), isNot(signatureOf([it('f0010', 200)])));
    });

    test('a meal repeated three times is offered, twice is not', () {
      final s = profiled();
      for (var i = 0; i < 2; i++) {
        s.meals.add(meal(daysAgo(i), [it('f0010', 200)]));
      }
      expect(repeatedMeals(s), isEmpty);

      s.meals.add(meal(daysAgo(2), [it('f0010', 200)]));
      final found = repeatedMeals(s);
      expect(found, hasLength(1));
      expect(found.single.count, 3);
    });

    test('a meal already saved is never offered again', () {
      final s = profiled();
      for (var i = 0; i < 4; i++) {
        s.meals.add(meal(daysAgo(i), [it('f0010', 200)]));
      }
      expect(repeatedMeals(s), hasLength(1));

      s.nutrition.templates.add(MealTemplate(id: 'mt1', n: 'Usual', items: [it('f0010', 200)]));
      expect(repeatedMeals(s), isEmpty);
    });

    test('a recipe that makes several portions prices one of them', () {
      // What separates a recipe from a saved meal. A pot of stew is written down once, as the
      // pot; everything that reads it — the list, the log, the day plan — wants a bowl.
      final stew = MealTemplate(
        id: 'mt1',
        n: 'Stew',
        servings: 4,
        items: [it('f0010', 800), it('f0107', 600)],
      );
      expect(stew.batchKcal, closeTo(stew.kcal * 4, 0.01));
      expect(stew.portion(), hasLength(2));
      expect(stew.portion().first.g, 200);
      expect(stew.portion().first.kcal, closeTo(stew.items.first.kcal / 4, 0.01));
    });

    test('a recipe with no servings set is one portion, not a crash', () {
      // `servings` is nullable so a recipe nobody batch-cooks stays out of the export, which
      // means every reader has to cope with its absence.
      final one = MealTemplate(id: 'mt1', n: 'Toast', items: [it('f0114', 60)]);
      expect(one.servings, isNull);
      expect(one.perServing, 1);
      expect(one.kcal, closeTo(one.batchKcal, 0.01));
      expect(one.toJson().containsKey('servings'), isFalse);
      expect(one.toJson().containsKey('slot'), isFalse);
    });

    test('a batch recipe already saved is never offered back as a repeat', () {
      // The signature has to be taken over a *portion*, or a four-serving stew is offered as
      // something to save again every time a bowl of it is logged.
      final s = profiled();
      for (var i = 0; i < 4; i++) {
        s.meals.add(meal(daysAgo(i), [it('f0010', 200)]));
      }
      s.nutrition.templates.add(MealTemplate(
        id: 'mt1',
        n: 'Batch',
        servings: 4,
        items: [it('f0010', 800)],
      ));
      expect(repeatedMeals(s), isEmpty);
    });

    test('a recipe filed under a meal keeps that filing across a change of meal count', () {
      // `MealTemplate.slot` is a name and not the numeric index `Meal.slot` carries, because
      // index 2 is a snack under a four-meal day and lunch under a six-meal one.
      final s = profiled();
      s.nutrition.templates.add(MealTemplate(id: 'mt1', n: 'Usual', slot: 'Breakfast'));
      s.nutrition.goal.meals = 4;
      final under4 = s.nutrition.templates.first.slot;
      s.nutrition.goal.meals = 6;
      expect(s.nutrition.templates.first.slot, under4);
      expect(under4, 'Breakfast');
    });

    test('saved meals are ordered by use, then by recency', () {
      final s = profiled();
      s.nutrition.templates.addAll([
        MealTemplate(id: 'a', n: 'Rare', used: 1, last: 9000),
        MealTemplate(id: 'b', n: 'Often', used: 9, last: 1000),
        MealTemplate(id: 'c', n: 'Also often', used: 9, last: 5000),
      ]);
      // A breakfast eaten every weekday outranks last night's dinner.
      expect(orderedTemplates(s).map((x) => x.id), ['c', 'b', 'a']);
    });

    test('logged days come back newest first, and the target day is excluded', () {
      final s = profiled();
      s.meals
        ..add(meal(daysAgo(3), [it('f0010', 100)]))
        ..add(meal(daysAgo(1), [it('f0010', 100)]))
        ..add(meal(daysAgo(0), [it('f0010', 100)]));
      expect(loggedDays(s), [daysAgo(0), daysAgo(1), daysAgo(3)]);
      expect(loggedDays(s, excluding: daysAgo(0)), [daysAgo(1), daysAgo(3)]);
    });

    test('an empty meal is not something to repeat', () {
      final s = profiled();
      for (var i = 0; i < 4; i++) {
        s.meals.add(meal(daysAgo(i), []));
      }
      expect(repeatedMeals(s), isEmpty);
      expect(loggedDays(s), isEmpty);
    });
  });

  group('the meal split', () {
    test('shares add up to the whole day', () {
      for (var n = 1; n <= 8; n++) {
        final g = NutritionGoal(meals: n.toDouble());
        final split = mealSplit(g);
        expect(split, hasLength(n), reason: '$n meals');
        expect(split.fold(0.0, (a, s) => a + s.$2), closeTo(1, 1e-9), reason: '$n meals');
      }
    });

    test('a count the table has no shape for is numbered, not left as a template', () {
      // Only reachable from an imported or hand-edited state; the control offers 2 to 6.
      final split = mealSplit(NutritionGoal(meals: 7));
      expect(split, hasLength(7));
      expect(split.first.$1, 'Meal 1');
      expect(split.last.$1, 'Meal 7');
      for (final s in split) {
        expect(s.$1, isNot(contains('{0}')));
      }
    });

    test('an unchosen plan is four meals', () {
      expect(mealsPerDay(NutritionGoal()), 4);
      expect(goalMode(NutritionGoal()), 'maintain');
    });
  });
}
