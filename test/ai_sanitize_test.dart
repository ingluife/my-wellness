import 'package:flutter_test/flutter_test.dart';
import 'package:my_open_gym/domain/ai/meal_photo_draft.dart';
import 'package:my_open_gym/domain/ai/meal_photo_sanitize.dart';
import 'package:my_open_gym/domain/foods.dart';

/// The gate between what a model said and what the app is willing to put in a food log.
///
/// Pure Dart — no Flutter binding, no bundle, no network. The catalogue arrives as a function, so
/// every bound here is checked against a fixture rather than against whatever `foods.json`
/// happens to hold this month.
void main() {
  // Two stand-ins with round numbers, so an arithmetic slip is visible by eye.
  const chicken = Food(
    id: 'f0001', n: 'Chicken breast', cat: 'protein',
    kcal: 165, p: 31, c: 0, f: 3.6,
  );
  const rice = Food(
    id: 'f0002', n: 'Rice, cooked', cat: 'carb',
    kcal: 130, p: 2.7, c: 28, f: 0.3,
  );
  const catalogue = {'f0001': chicken, 'f0002': rice};

  MealDraft run(Object? raw) =>
      sanitizeMealGuess(raw, lookup: (id) => catalogue[id]);

  Map<String, dynamic> answer(List<Map<String, dynamic>> items,
          {String confidence = 'high', bool? notFood}) =>
      {
        'items': items,
        'confidence': confidence,
        'notFood': ?notFood,
      };

  group('the envelope', () {
    test('anything that is not a map is unreadable, and never throws', () {
      for (final junk in <Object?>[null, 'nope', 42, <int>[1, 2], true]) {
        final d = run(junk);
        expect(d.isEmpty, isTrue);
        expect(d.has(DraftProblem.unreadable), isTrue, reason: 'for $junk');
      }
    });

    test('notFood is its own answer, not an error', () {
      final d = run(answer(const [], notFood: true));
      expect(d.isEmpty, isTrue);
      expect(d.has(DraftProblem.notFood), isTrue);
      expect(d.has(DraftProblem.unreadable), isFalse);
    });

    test('no items at all reads as noItems', () {
      expect(run(answer(const [])).has(DraftProblem.noItems), isTrue);
      expect(run({'confidence': 'high'}).has(DraftProblem.noItems), isTrue);
    });

    test('an unrecognised confidence reads as low, not as a crash', () {
      // Erring towards "unsure" is the right direction for a number the user is about to trust.
      Object one(String c) => answer([
            {'fid': 'f0001', 'name': 'Chicken', 'grams': 100}
          ], confidence: c);

      expect(run(one('extremely')).confidence, DraftConfidence.low);
      expect(run(one('')).confidence, DraftConfidence.low);
      expect(run(one('high')).confidence, DraftConfidence.high);
      expect(run(one('medium')).confidence, DraftConfidence.medium);
    });
  });

  group('catalogue hits', () {
    test('macros come from the food, never from the model', () {
      // The model is given every chance to be believed and must be ignored anyway.
      final d = run(answer([
        {
          'fid': 'f0001',
          'name': 'Chicken breast',
          'grams': 200,
          'per100': {'kcal': 9999, 'p': 0, 'c': 99, 'f': 99},
        }
      ]));

      final item = d.items.single.toMealItem();
      expect(item.kcal, chicken.kcal * 200 / 100);
      expect(item.p, chicken.p * 200 / 100);
      expect(item.c, chicken.c * 200 / 100);
      expect(item.f, chicken.f * 200 / 100);
      expect(item.fid, 'f0001');
      // A catalogue food carries no name of its own in the log — the id resolves to one.
      expect(item.n, isNull);
    });

    test('an unknown id becomes free-form rather than the zero-macro placeholder', () {
      // `foods.or(id)` returns an "Unknown food" with every macro at zero. Logging that would put
      // a silent 0 kcal row in the day, which is worse than dropping the item outright.
      final d = run(answer([
        {
          'fid': 'f9999',
          'name': 'Something else',
          'grams': 100,
          'per100': {'kcal': 200, 'p': 10, 'c': 20, 'f': 8},
        }
      ]));

      expect(d.has(DraftProblem.unknownFid), isTrue);
      final only = d.items.single;
      expect(only.isFreeForm, isTrue);
      expect(only.toMealItem().fid, isNull);
      expect(only.toMealItem().n, 'Something else');
      expect(only.toMealItem().kcal, 200);
    });

    test('an unknown id with no macros to fall back on is dropped, not zeroed', () {
      final d = run(answer([
        {'fid': 'f9999', 'name': 'Mystery', 'grams': 100}
      ]));
      expect(d.items, isEmpty);
      expect(d.has(DraftProblem.noMacros), isTrue);
      expect(d.has(DraftProblem.noItems), isTrue);
    });

    test('two rows of the same food are one food', () {
      final d = run(answer([
        {'fid': 'f0001', 'name': 'Chicken', 'grams': 100, 'gramsLow': 80, 'gramsHigh': 120},
        {'fid': 'f0001', 'name': 'Chicken', 'grams': 50, 'gramsLow': 40, 'gramsHigh': 60},
      ]));
      expect(d.items, hasLength(1));
      expect(d.items.single.grams, 150);
      expect(d.items.single.gramsLow, 120);
      expect(d.items.single.gramsHigh, 180);
    });

    test('two different foods stay two foods', () {
      final d = run(answer([
        {'fid': 'f0001', 'name': 'Chicken', 'grams': 100},
        {'fid': 'f0002', 'name': 'Rice', 'grams': 150},
      ]));
      expect(d.items, hasLength(2));
    });
  });

  group('grams', () {
    test('a portion that is not a usable number takes the item with it', () {
      for (final bad in <Object?>[null, 0, -50, 'abc', double.nan, double.infinity]) {
        final d = run(answer([
          {'fid': 'f0001', 'name': 'Chicken', 'grams': bad}
        ]));
        expect(d.items, isEmpty, reason: 'for $bad');
      }
    });

    test('an implausible portion is clamped rather than believed', () {
      final d = run(answer([
        {'fid': 'f0001', 'name': 'Chicken', 'grams': 50000}
      ]));
      expect(d.items.single.grams, 2000);
      expect(d.has(DraftProblem.gramsClamped), isTrue);
    });

    test('a plausible portion is left exactly alone', () {
      final d = run(answer([
        {'fid': 'f0001', 'name': 'Chicken', 'grams': 173}
      ]));
      expect(d.items.single.grams, 173);
      expect(d.has(DraftProblem.gramsClamped), isFalse);
    });
  });

  group('the range', () {
    test('a missing range collapses to the estimate', () {
      final d = run(answer([
        {'fid': 'f0001', 'name': 'Chicken', 'grams': 100}
      ]));
      final i = d.items.single;
      expect(i.gramsLow, 100);
      expect(i.gramsHigh, 100);
    });

    test('a swapped low and high is sorted, not rejected', () {
      // Three useful numbers arrived; the order they arrived in is not worth losing them over.
      final d = run(answer([
        {'fid': 'f0001', 'name': 'Chicken', 'grams': 100, 'gramsLow': 140, 'gramsHigh': 70}
      ]));
      final i = d.items.single;
      expect(i.gramsLow, 70);
      expect(i.gramsHigh, 140);
    });

    test('a uselessly wide range is capped to something reviewable', () {
      final d = run(answer([
        {'fid': 'f0001', 'name': 'Chicken', 'grams': 100, 'gramsLow': 1, 'gramsHigh': 1900}
      ]));
      final i = d.items.single;
      expect(i.gramsLow, closeTo(100 / 3, 1e-9));
      expect(i.gramsHigh, 300);
    });

    test('low and high always bracket the estimate', () {
      final d = run(answer([
        {'fid': 'f0001', 'name': 'Chicken', 'grams': 100, 'gramsLow': 150, 'gramsHigh': 160}
      ]));
      final i = d.items.single;
      expect(i.gramsLow, lessThanOrEqualTo(i.grams));
      expect(i.gramsHigh, greaterThanOrEqualTo(i.grams));
    });

    test('the draft reports a calorie band, not just a figure', () {
      final d = run(answer([
        {'fid': 'f0001', 'name': 'Chicken', 'grams': 100, 'gramsLow': 50, 'gramsHigh': 200}
      ]));
      expect(d.kcal, chicken.kcal);
      expect(d.kcalLow, closeTo(chicken.kcal * 0.5, 1e-9));
      expect(d.kcalHigh, closeTo(chicken.kcal * 2, 1e-9));
    });
  });

  group('free-form macros', () {
    Map<String, dynamic> freeForm(Map<String, dynamic> per100, {double grams = 100}) =>
        answer([
          {'name': 'Some stew', 'grams': grams, 'per100': per100}
        ]);

    test('impossible per-100 g values are clamped to the same bounds a typed food gets', () {
      final d = run(freeForm({'kcal': 5000, 'p': 900, 'c': 900, 'f': 900}));
      final p = d.items.single.per100!;
      expect(p.p, 100);
      expect(p.c, 100);
      expect(p.f, 100);
      expect(p.kcal, lessThanOrEqualTo(900));
    });

    test('energy that disagrees with the macros loses to them', () {
      // 10 g protein + 20 g carb + 5 g fat = 165 kcal. A claimed 600 is not a rounding error.
      final d = run(freeForm({'kcal': 600, 'p': 10, 'c': 20, 'f': 5}));
      expect(d.items.single.per100!.kcal, closeTo(165, 1e-9));
      expect(d.has(DraftProblem.kcalRecomputed), isTrue);
    });

    test('energy that merely rounds differently is left alone', () {
      // 4*10 + 4*20 + 9*5 = 165; a claimed 170 is well inside tolerance.
      final d = run(freeForm({'kcal': 170, 'p': 10, 'c': 20, 'f': 5}));
      expect(d.items.single.per100!.kcal, 170);
      expect(d.has(DraftProblem.kcalRecomputed), isFalse);
    });

    test('a low-calorie food is not corrected over a few kcal', () {
      // The absolute floor exists for exactly this: 4*1+4*4+9*0 = 20 against a claimed 30 is a
      // 50% drift and completely unremarkable for a vegetable.
      final d = run(freeForm({'kcal': 30, 'p': 1, 'c': 4, 'f': 0}));
      expect(d.items.single.per100!.kcal, 30);
      expect(d.has(DraftProblem.kcalRecomputed), isFalse);
    });

    test('a missing energy figure is derived rather than left at zero', () {
      final d = run(freeForm({'kcal': 0, 'p': 10, 'c': 20, 'f': 5}));
      expect(d.items.single.per100!.kcal, closeTo(165, 1e-9));
    });

    test('an all-zero food is dropped rather than logged as nothing', () {
      final d = run(freeForm({'kcal': 0, 'p': 0, 'c': 0, 'f': 0}));
      expect(d.items, isEmpty);
      expect(d.has(DraftProblem.noMacros), isTrue);
    });

    test('macros scale with the portion', () {
      final d = run(freeForm({'kcal': 200, 'p': 10, 'c': 20, 'f': 8}, grams: 250));
      final item = d.items.single.toMealItem();
      expect(item.kcal, 500);
      expect(item.p, 25);
      expect(item.g, 250);
      expect(item.fid, isNull);
      expect(item.n, 'Some stew');
    });
  });

  group('the item cap', () {
    test('the cap drops the garnish, not the steak', () {
      final d = run(answer([
        for (var i = 0; i < 20; i++)
          {'fid': 'f0002', 'name': 'Filler $i', 'grams': 1.0 + i},
        {'fid': 'f0001', 'name': 'The steak', 'grams': 400},
      ]));

      expect(d.has(DraftProblem.tooManyItems), isTrue);
      // Everything left is a catalogue food; the steak must be among them.
      expect(d.items.any((i) => i.food?.id == 'f0001'), isTrue,
          reason: 'the largest item must survive the cap');
    });
  });

  test('a rich, ordinary answer produces exactly what you would expect', () {
    final d = run(answer([
      {'fid': 'f0001', 'name': 'Chicken breast', 'grams': 150, 'gramsLow': 120, 'gramsHigh': 190},
      {'fid': 'f0002', 'name': 'Rice', 'grams': 200, 'gramsLow': 160, 'gramsHigh': 260},
      {
        'name': 'Peanut sauce',
        'grams': 30,
        'per100': {'kcal': 550, 'p': 22, 'c': 20, 'f': 44},
      },
    ]));

    expect(d.problems, isEmpty);
    expect(d.items, hasLength(3));
    expect(d.confidence, DraftConfidence.high);
    expect(
      d.kcal,
      closeTo(chicken.kcal * 1.5 + rice.kcal * 2 + 550 * 0.3, 1e-9),
    );
    expect(d.kcalLow, lessThan(d.kcal));
    expect(d.kcalHigh, greaterThan(d.kcal));
  });
}
