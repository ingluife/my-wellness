import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/day_plan_source.dart';
import 'package:my_wellness/domain/dishes.dart';
import 'package:my_wellness/domain/foods.dart';

/// The bundled dish catalogue, checked the way `foods_test.dart` checks the food one.
///
/// A dish is a list of ids and grams in a TSV, which is exactly the kind of data that goes
/// quietly wrong: a mistyped id renders as a blank row, a misplaced decimal puts 700 g of oil
/// in somebody's breakfast, and neither shows up until it is in front of a user. The generator
/// refuses to emit most of these; this is the half that has to hold after it has.
void main() {
  late List<Map<String, dynamic>> raw;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await foods.load();
    raw = [
      for (final e in jsonDecode(File('assets/data/dishes.json').readAsStringSync()) as List)
        Map<String, dynamic>.from(e as Map)
    ];
  });

  test('the catalogue is the size it says it is', () {
    // Capped on purpose: the planner prefers the user's own recipes, so this only has to cover
    // the fortnight before there are any. Every dish past the cap costs eleven translations and
    // buys almost nothing. Raising it is a decision, not a drift.
    expect(raw.length, lessThanOrEqualTo(60));
    expect(raw.length, greaterThanOrEqualTo(40));
  });

  test('every id is unique and permanent-looking', () {
    final ids = [for (final d in raw) d['id'] as String];
    expect(ids.toSet(), hasLength(ids.length));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^d\d{4}$')));
    }
  });

  test('every dish names a food that exists', () {
    for (final d in raw) {
      for (final p in d['parts'] as List) {
        final fid = (p as Map)['fid'];
        expect(foods[fid as String?], isNotNull, reason: '${d['id']} refers to $fid');
      }
    }
  });

  test('every dish is filed under a real meal and a real kitchen', () {
    const slots = {'breakfast', 'lunch', 'snack', 'dinner'};
    for (final d in raw) {
      final mine = [for (final s in d['slots'] as List) s as String];
      expect(mine, isNotEmpty, reason: d['id'] as String);
      for (final s in mine) {
        expect(slots, contains(s), reason: '${d['id']} is filed under $s');
      }
      for (final c in d['cuisines'] as List) {
        expect(cuisines, contains(c), reason: '${d['id']} is tagged $c');
      }
    }
  });

  test('every role is one the planner knows how to scale', () {
    final known = {for (final r in PartRole.values) r.name};
    for (final d in raw) {
      for (final p in d['parts'] as List) {
        expect(known, contains((p as Map)['role']), reason: d['id'] as String);
      }
      // A dish of one thing is a food, and the food library already has those.
      expect((d['parts'] as List).length, greaterThanOrEqualTo(2), reason: d['id'] as String);
    }
  });

  test('every unit part says what one unit is', () {
    // A `unit` moves in whole household measures, and without a step there is nothing to move
    // in — it would silently resize like a `flex` and put 2.4 slices of bread on the plate.
    for (final d in raw) {
      for (final p in d['parts'] as List) {
        if ((p as Map)['role'] != 'unit') continue;
        expect(p['step'], isNotNull, reason: '${d['id']}/${p['fid']}');
        expect(p['step'], greaterThan(0), reason: '${d['id']}/${p['fid']}');
      }
    }
  });

  group('at the serving it is written down as', () {
    test('every dish is a plate somebody would recognise', () {
      for (final d in raw) {
        var kcal = 0.0;
        for (final p in d['parts'] as List) {
          final food = foods.or((p as Map)['fid'] as String);
          kcal += food.kcal * (p['g'] as num) / 100;
        }
        // Wide, because a snack and a roast dinner are both in here. The point is to catch a
        // misplaced decimal, not to second-guess the recipe.
        expect(kcal, greaterThan(120), reason: '${d['id']} ${d['n']}');
        expect(kcal, lessThan(1200), reason: '${d['id']} ${d['n']}');
      }
    });

    test('nothing rich is on it by the plateful', () {
      // The same rule the day planner enforces on its own assemblies, applied to the catalogue
      // so a seed-file mistake cannot smuggle 240 g of cheese in through the other door.
      for (final d in raw) {
        for (final p in d['parts'] as List) {
          final food = foods.or((p as Map)['fid'] as String);
          final grams = (p['g'] as num).toDouble();
          if (food.kcal >= 600) {
            expect(grams, lessThanOrEqualTo(30), reason: '${d['id']}: ${food.n}');
          } else if (food.kcal >= 300) {
            expect(grams, lessThanOrEqualTo(80), reason: '${d['id']}: ${food.n}');
          }
        }
      }
    });
  });

  group('the loader', () {
    setUpAll(() => dishes.load());

    test('reads the whole catalogue', () {
      expect(dishes.db, hasLength(raw.length));
      expect(dishes.isLoaded, isTrue);
    });

    test('a slot with no name in the split matches everything', () {
      // 'All day' is a real split, and a numbered 'Meal 3' is reachable from an imported state.
      // Neither is something a dish can disagree with.
      final dish = dishes.db.first;
      expect(dish.fitsSlot('All day'), isTrue);
      expect(dish.fitsSlot('Meal 3'), isTrue);
    });

    test('every kitchen can fill every slot, with enough choice to reshuffle', () {
      for (final cuisine in cuisines) {
        for (final slot in ['Breakfast', 'Lunch', 'Snack', 'Dinner']) {
          final got = dishes.forSlot(slot, cuisine: cuisine);
          for (final d in got.mine) {
            expect(d.cuisines.any((c) => c == cuisine || c == 'generic'), isTrue,
                reason: '$cuisine $slot: ${d.n}');
          }
          // Three is the point at which "show me another" does something, and `forSlot` is
          // supposed to guarantee it by lending a thin kitchen the universal dishes. The
          // catalogue holds exactly one East Asian breakfast; without that rule a Korean
          // profile was handed congee on every seed.
          expect(got.mine.length, greaterThanOrEqualTo(3), reason: '$cuisine $slot');
        }
      }
    });
  });

  group('the kitchen a profile cooks from', () {
    test('follows the interface language until the user says otherwise', () {
      final s = AppState.defaults()..lang = 'it';
      expect(cuisineOf(s), 'mediterranean');
      s.lang = 'ko';
      expect(cuisineOf(s), 'asian');
      // A language with nothing mapped to it falls through rather than guessing.
      s.lang = 'en';
      expect(cuisineOf(s), 'generic');
    });

    test('an explicit choice wins, and a nonsense one does not', () {
      final s = AppState.defaults()..lang = 'it';
      s.nutrition.goal.cuisine = 'asian';
      expect(cuisineOf(s), 'asian');
      // Reachable from a hand-edited or newer-build state.
      s.nutrition.goal.cuisine = 'klingon';
      expect(cuisineOf(s), 'mediterranean');
    });

    test('choosing one keeps the nutrition key droppable', () {
      // The discipline every field in this model follows: never chosen has to stay
      // distinguishable from chosen-the-default, or a fresh profile stops exporting the same
      // JSON openGym does.
      final s = AppState.defaults();
      expect(s.nutrition.goal.isDefault, isTrue);
      expect(s.nutrition.goal.toJson().containsKey('cuisine'), isFalse);
      s.nutrition.goal.cuisine = 'latin';
      expect(s.nutrition.goal.isDefault, isFalse);
      expect(s.nutrition.goal.toJson()['cuisine'], 'latin');
    });
  });
}
