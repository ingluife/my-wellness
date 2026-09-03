import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/foods.dart';

/// Guards the generated catalogue.
///
/// `assets/data/foods.json` is written by tool/gen_foods.mjs from a USDA dataset, so nobody
/// reviews it line by line. These are the checks that would have caught the bad matches the
/// curation pass turned up by hand — a food whose macros do not add up to its calories, a
/// duplicate id, a protein that is mostly water.
void main() {
  final raw = jsonDecode(File('assets/data/foods.json').readAsStringSync()) as List;
  final all = [for (final e in raw) Food.fromJson(Map<String, dynamic>.from(e as Map))];

  test('the catalogue is not empty and covers every category', () {
    expect(all.length, greaterThan(150));
    for (final cat in foodCategories) {
      expect(all.where((f) => f.cat == cat), isNotEmpty, reason: cat);
    }
  });

  test('every id is unique and permanent-looking', () {
    final ids = <String>{};
    for (final f in all) {
      expect(f.id, matches(RegExp(r'^f\d{4}$')), reason: f.n);
      expect(ids.add(f.id), isTrue, reason: 'duplicate ${f.id}');
    }
  });

  test('every food carries a name, a known category and a source record', () {
    for (final f in all) {
      expect(f.n, isNotEmpty);
      expect(foodCategories, contains(f.cat), reason: f.n);
      expect(f.src, startsWith('usda:'), reason: f.n);
      // A photograph is optional — a food with no confident match keeps its category glyph —
      // but a filename, when there is one, has to be the one sync_food_media.sh writes.
      if (f.img != null) {
        expect(f.img, endsWith('.jpg'), reason: f.n);
        expect(f.img, startsWith(f.id), reason: f.n);
      }
    }
  });

  group('household portions', () {
    test('most of the catalogue offers at least one', () {
      final withPortions = all.where((f) => f.portions.isNotEmpty).length;
      // 199 of 226 at the time of writing; the floor guards against a filter change that
      // quietly throws most of them away.
      expect(withPortions, greaterThan(180));
    });

    test('no portion is a bare weight or volume unit', () {
      // The trap this exists for: the bulk USDA dataset drops the `amount` field the API
      // carries, so `{modifier: "oz", gramWeight: 113}` is FOUR ounces of chicken. Rendered as
      // "1 oz" it would be wrong by a factor of four, and wrong invisibly — every number on
      // screen would still look plausible.
      final ambiguous = RegExp(
          r'^(oz|lb|lbs|fl oz|g|kg|mg|ml|l|liter|litre|gram|grams|pound|pounds|ounce|ounces)$',
          caseSensitive: false);
      for (final f in all) {
        for (final p in f.portions) {
          expect(ambiguous.hasMatch(p.n), isFalse, reason: '${f.n}: "${p.n}"');
        }
      }
    });

    test('no portion is a way of buying rather than a way of eating', () {
      final bulk = RegExp(r'package|bunch|as purchased|container|carton|loaf|yields',
          caseSensitive: false);
      for (final f in all) {
        for (final p in f.portions) {
          expect(bulk.hasMatch(p.n), isFalse, reason: '${f.n}: "${p.n}"');
        }
      }
    });

    test('every portion is a plausible single serving', () {
      for (final f in all) {
        for (final p in f.portions) {
          expect(p.g, greaterThan(0), reason: '${f.n}: ${p.n}');
          expect(p.g, lessThanOrEqualTo(400), reason: '${f.n}: ${p.n}');
          expect(p.n, isNotEmpty, reason: f.n);
          // Parenthetical sizing is stripped — nobody eats by 2-3/8" diameter.
          expect(p.n, isNot(contains('(')), reason: '${f.n}: ${p.n}');
        }
      }
    });

    test('portions read smallest first, and are named the way people speak', () {
      final egg = all.firstWhere((f) => f.n == 'Egg, whole');
      expect(egg.portions.map((p) => p.n), containsAll(['small', 'medium', 'large']));
      for (var i = 1; i < egg.portions.length; i++) {
        expect(egg.portions[i].g, greaterThanOrEqualTo(egg.portions[i - 1].g));
      }
      // A natural count noun beats a cup: eggs are eaten by the egg.
      expect(egg.portions.first.n, isNot(startsWith('cup')));
    });

    test('a portion resolves to the same macros as its grams', () {
      final bread = all.firstWhere((f) => f.n == 'White bread');
      final slice = bread.portions.firstWhere((p) => p.n == 'slice');
      final item = bread.portion(slice.g);
      expect(item.g, slice.g);
      expect(item.kcal, closeTo(bread.kcal * slice.g / 100, 1e-9));
    });
  });

  group('fibre', () {
    test('almost every food carries one', () {
      expect(all.where((f) => f.fib != null).length, greaterThan(200));
    });

    test('it scales with the portion, and is null when unknown', () {
      final oats = all.firstWhere((f) => f.n == 'Oats');
      expect(oats.fib, greaterThan(0));
      expect(oats.fibreIn(200), closeTo(oats.fib! * 2, 1e-9));

      const bare = Food(id: 'x', n: 'x', cat: 'veg', kcal: 1, p: 0, c: 0, f: 0);
      expect(bare.fibreIn(100), isNull);
    });

    test('fibre never exceeds the carbohydrate it is part of', () {
      for (final f in all) {
        if (f.fib == null) continue;
        expect(f.fib, lessThanOrEqualTo(f.c + 0.51), reason: '${f.n}: ${f.fib}F vs ${f.c}C');
      }
    });
  });

  group('attribution', () {
    test('a food with a photograph credits whoever took it', () {
      // Most of these images are CC BY or CC BY-SA, so the credit has to reach the screen.
      final withPhoto = all.where((f) => f.img != null).toList();
      expect(withPhoto, isNotEmpty);
      for (final f in withPhoto) {
        expect(f.credit, isNotNull, reason: '${f.n} has a photo but nothing to credit');
        expect(f.credit, isNotEmpty, reason: f.n);
      }
    });

    test('a food with no photograph credits nobody', () {
      const bare = Food(id: 'f9998', n: 'x', cat: 'veg', kcal: 1, p: 0, c: 0, f: 0);
      expect(bare.credit, isNull);
    });

    test('licence codes render the way Creative Commons writes them', () {
      String credit(String lic) =>
          Food(id: 'x', n: 'x', cat: 'veg', kcal: 1, p: 0, c: 0, f: 0, by: 'Jane', lic: lic)
              .credit!;
      expect(credit('by-sa-4.0'), 'Jane (CC BY-SA 4.0)');
      expect(credit('by-2.0'), 'Jane (CC BY 2.0)');
      expect(credit('cc0-1.0'), 'Jane (CC0 1.0)');
      expect(credit('pdm-1.0'), 'Jane (Public domain)');
    });

    test('an unknown photographer still names the licence', () {
      const anon = Food(
          id: 'x', n: 'x', cat: 'veg', kcal: 1, p: 0, c: 0, f: 0, lic: 'by-sa-4.0');
      expect(anon.credit, 'CC BY-SA 4.0');
    });

    test('no non-commercial licence is ever bundled', () {
      // NC would make the catalogue undistributable with the app; the fetcher filters it out
      // and this is the check that it stayed filtered.
      for (final f in all) {
        expect(f.lic ?? '', isNot(contains('nc')), reason: f.n);
      }
    });
  });

  test('macros add up to the stated calories', () {
    // 4/4/9 kcal per gram is the rule of thumb, not what USDA applies: it uses food-specific
    // Atwater factors, so fibre-heavy greens and citrus legitimately come out well under what
    // 4/4/9 predicts (a lemon is 9.3 g of carbohydrate and 29 kcal, most of it fibre and citric
    // acid). Below 50 kcal that correction dominates the number, and alcohol carries 7 kcal/g
    // that no macro column holds at all. Above the floor a 25% band catches a transcription
    // error without failing on biology.
    for (final f in all) {
      if (f.kcal < 50) continue;
      if (f.cat == 'drink') continue;
      final fromMacros = f.p * 4 + f.c * 4 + f.f * 9;
      expect(fromMacros, closeTo(f.kcal, f.kcal * 0.25),
          reason: '${f.n}: ${f.kcal} kcal vs ${fromMacros.toStringAsFixed(0)} from macros');
    }
  });

  test('no macro is negative or absurd', () {
    for (final f in all) {
      for (final v in [f.kcal, f.p, f.c, f.f]) {
        expect(v, greaterThanOrEqualTo(0), reason: f.n);
      }
      // Per 100 g, nothing can hold more than 100 g of anything.
      expect(f.p, lessThanOrEqualTo(100), reason: f.n);
      expect(f.c, lessThanOrEqualTo(100), reason: f.n);
      expect(f.f, lessThanOrEqualTo(100), reason: f.n);
      expect(f.kcal, lessThanOrEqualTo(900), reason: f.n);
    }
  });

  test('foods filed as protein actually are one', () {
    // The bad match this catches for real: "Scallops" resolving to scallop *squash*, which is
    // 1.2 g of protein and sat under protein until a coherence sweep found it. Hummus failed
    // this too and was recategorised rather than excused — at 2.8 g per 100 kcal it is a dip.
    for (final f in all.where((f) => f.cat == 'protein')) {
      expect(f.proteinDensity, greaterThan(4),
          reason: '${f.n} is ${f.p}P per ${f.kcal} kcal');
    }
  });

  test('nothing filed as protein is a composite dish in disguise', () {
    // Density alone is not enough to catch a bad match. "Ham" resolved to LEAN POCKETS Ham 'N
    // Cheddar — a frozen filled pastry at 32.5 g of carbohydrate, whose density of 4.48 cleared
    // the floor above, so it sat in the catalogue as a meat and the day planner offered it as
    // one. Starch is what separates a prepared dish from an ingredient here: the pulses are the
    // legitimate ceiling at 27.4 g (chickpeas), and the next food down is edamame at 8.9, so
    // there is real room between the honest maximum and the pastry.
    for (final f in all.where((f) => f.cat == 'protein')) {
      expect(f.c, lessThan(30), reason: '${f.n} carries ${f.c}C per 100 g');
    }
  });

  test('protein density ranks by what a calorie budget can afford', () {
    final chicken = all.firstWhere((f) => f.n == 'Chicken breast');
    final parmesan = all.firstWhere((f) => f.n == 'Parmesan');
    // Parmesan holds the most protein per 100 g in the whole catalogue and is still a far worse
    // way to buy it than chicken breast, because 392 of its calories come along for the ride.
    // This is the whole reason the browse sorts on density rather than on grams.
    expect(parmesan.p, greaterThan(chicken.p));
    expect(chicken.proteinDensity, greaterThan(parmesan.proteinDensity * 2));
  });

  group('the index', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await foods.load();
    });

    test('looks a food up by id', () {
      final chicken = all.firstWhere((f) => f.n == 'Chicken breast');
      expect(foods[chicken.id]?.n, 'Chicken breast');
      expect(foods[null], isNull);
    });

    test('an unknown id still renders rather than taking the view down', () {
      final ghost = foods.or('f9999');
      expect(ghost.missing, isTrue);
      expect(ghost.n, isNotEmpty);
      expect(ghost.kcal, 0);
    });

    test('a portion scales from per-100 g', () {
      final chicken = foods.db.firstWhere((f) => f.n == 'Chicken breast');
      final item = chicken.portion(200);
      expect(item.g, 200);
      expect(item.kcal, closeTo(chicken.kcal * 2, 1e-9));
      expect(item.p, closeTo(chicken.p * 2, 1e-9));
      expect(item.fid, chicken.id);
    });

    test('the profile\'s own foods join the same index', () {
      final s = AppState.defaults();
      s.nutrition.foods.add(CustomFood(id: 'cf1', n: 'Whey shake', cat: 'protein', kcal: 380, p: 80));
      foods.registerCustom(s.nutrition.foods);

      expect(foods['cf1']?.n, 'Whey shake');
      expect(foods['cf1']?.custom, isTrue);
      // Customs come first in the searchable list, as the exercise library does.
      expect(foods.all(s).first.id, 'cf1');
      expect(foods.search(s, 'whey').single.id, 'cf1');

      // Deregistering leaves the bundled catalogue untouched.
      foods.registerCustom([]);
      expect(foods['cf1'], isNull);
      expect(foods.db, isNotEmpty);
    });

    test('protein sources come back densest first', () {
      final s = AppState.defaults();
      final ranked = foods.proteinSources(s);
      expect(ranked, isNotEmpty);
      for (var i = 1; i < ranked.length; i++) {
        expect(ranked[i - 1].proteinDensity,
            greaterThanOrEqualTo(ranked[i].proteinDensity));
      }
      // Egg white is close to pure protein, so it should be at the very sharp end.
      expect(ranked.take(12).map((f) => f.n), contains('Egg white'));
    });
  });
}
