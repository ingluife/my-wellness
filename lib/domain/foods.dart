import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/models/app_state.dart';
import 'i18n.dart';

/// The bundled food catalogue — 226 foods with their macros per 100 g.
///
/// Generated from USDA FoodData Central by tool/gen_foods.mjs and bundled, for the same reason
/// the 1,324 exercises are: the app works with no network at all. Structured like [Exercises]
/// down to the `or()` placeholder, because a logged meal holds a food id and that lookup has to
/// keep working after a catalogue regeneration, a backup from another device, or a custom food
/// deleted somewhere else.
/// A household measure for a food: "1 slice = 29 g".
///
/// Grams are what the maths needs and what almost nobody can estimate. These come from USDA's
/// own portion tables, filtered in tool/gen_foods.mjs to the ones whose implied amount is
/// reliably one — see the comment there, because the trap is not obvious.
class FoodPortion {
  const FoodPortion({required this.n, required this.g});

  /// 'slice', 'medium', 'cup, chopped'. An English source string, so its own i18n key.
  final String n;

  final double g;

  factory FoodPortion.fromJson(Map<String, dynamic> j) =>
      FoodPortion(n: asStr(j['n']) ?? '', g: asNumOr(j['g'], 0));
}

class Food {
  const Food({
    required this.id,
    required this.n,
    required this.cat,
    required this.kcal,
    required this.p,
    required this.c,
    required this.f,
    this.img,
    this.src,
    this.by,
    this.lic,
    this.fib,
    this.sug,
    this.sat,
    this.salt,
    this.portions = const [],
    this.custom = false,
    this.missing = false,
  });

  final String id;

  /// Display name, and its own i18n key.
  final String n;

  /// protein | dairy | carb | veg | fruit | fat | drink | other
  final String cat;

  /// Per 100 g, always. A portion is grams x this / 100.
  final double kcal;
  final double p;
  final double c;
  final double f;

  /// Filename under assets/food/, or null for a custom food. Absent art is normal, not an
  /// error: the photographs are fetched by a script and git-ignored, so a fresh checkout has
  /// none of them and every list still has to render.
  final String? img;

  /// `usda:171077` — which record the numbers came from, so any of them can be checked.
  final String? src;

  /// Grams of fibre per 100 g.
  ///
  /// Tracked but never given a target. Fibre is why a deficit is survivable — it is most of
  /// what makes a meal filling — but a fifth number to hit would work against teaching one
  /// thing at a time.
  final double? fib;

  /// Grams of sugar, saturated fat, and salt per 100 g. Same reasoning as [fib]: shown on the
  /// label, tracked, never targeted. The bundled catalogue carries none of these yet — they
  /// exist so a food you type in yourself can hold the rest of what its own label says.
  final double? sug;
  final double? sat;
  final double? salt;

  /// Household measures, smallest first. Empty for a custom food, and for the 27 catalogue
  /// foods whose USDA portions were all bulk or ambiguous.
  final List<FoodPortion> portions;

  /// Who took the photograph, and under what licence.
  ///
  /// Most of the images are CC-BY or CC-BY-SA, which requires the credit to travel with the
  /// work rather than sit in a file on GitHub. [FoodImage] renders it under the picture.
  final String? by;
  final String? lic;

  final bool custom;
  final bool missing;

  /// "Photo: Jane Doe (CC BY-SA 4.0)", or null when there is nothing to credit.
  String? get credit {
    if (by == null && lic == null) return null;
    final licence = lic == null ? null : _licenceName(lic!);
    if (by == null) return licence;
    return licence == null ? by : '$by ($licence)';
  }

  /// Grams of protein per 100 kcal.
  ///
  /// The number that actually answers "what should I eat more of". Ranking by protein per 100 g
  /// puts peanut butter (25 g) above chicken breast (22 g), which is true and useless: the
  /// peanut butter arrives with 600 kcal attached. Density is what a calorie budget cares
  /// about. Zero-calorie foods score 0 rather than dividing by it.
  double get proteinDensity => kcal <= 0 ? 0 : p / kcal * 100;

  factory Food.fromJson(Map<String, dynamic> j) => Food(
        id: asStr(j['id']) ?? '',
        n: asStr(j['n']) ?? '',
        cat: asStr(j['cat']) ?? 'other',
        kcal: asNumOr(j['kcal'], 0),
        p: asNumOr(j['p'], 0),
        c: asNumOr(j['c'], 0),
        f: asNumOr(j['f'], 0),
        img: asStr(j['img']),
        src: asStr(j['src']),
        by: asStr(j['by']),
        lic: asStr(j['lic']),
        fib: asNum(j['fib']),
        sug: asNum(j['sug']),
        sat: asNum(j['sat']),
        salt: asNum(j['salt']),
        portions: [
          for (final p in (j['por'] is List ? j['por'] as List : const []))
            if (p is Map) FoodPortion.fromJson(Map<String, dynamic>.from(p))
        ],
      );

  factory Food.fromCustom(CustomFood c) => Food(
        id: c.id,
        n: c.n,
        cat: c.cat,
        kcal: c.kcal,
        p: c.p,
        c: c.c,
        f: c.f,
        fib: c.fib,
        sug: c.sug,
        sat: c.sat,
        salt: c.salt,
        custom: true,
      );

  /// This food's contribution for a portion of [grams].
  MealItem portion(double grams) => MealItem(
        fid: id,
        n: custom || missing ? n : null,
        g: grams,
        kcal: kcal * grams / 100,
        p: p * grams / 100,
        c: c * grams / 100,
        f: f * grams / 100,
      );

  /// Scales a per-100 g label figure — [fib], [sug], [sat] or [salt] — to a portion of [grams].
  /// Null when the food carries no figure for it, so a nutrient never entered stays absent
  /// rather than showing up as zero.
  static double? per(double? per100, double grams) =>
      per100 == null ? null : per100 * grams / 100;
}

/// The catalogue order the library browses in, and the order category chips appear in:
/// what a lifter is looking for first.
///
/// 'other' comes last and is genuinely other — the condiments a dish is seasoned with, and the
/// default every food the user defines themselves lands in. It was missing from this list for
/// as long as the list existed, which meant a profile full of its own foods had no way to
/// filter down to them.
const foodCategories = <String>[
  'protein', 'dairy', 'carb', 'veg', 'fruit', 'fat', 'drink', 'other',
];

/// English display names; these strings are the i18n keys.
const foodCategoryName = <String, String>{
  'protein': 'Protein',
  'dairy': 'Dairy & eggs',
  'carb': 'Carbs',
  'veg': 'Vegetables',
  'fruit': 'Fruit',
  'fat': 'Fats & nuts',
  'drink': 'Drinks',
  'other': 'Other',
};

/// The glyph each category is drawn with when a food has no photograph.
const foodCategoryGlyph = <String, String>{
  'protein': 'fish',
  'dairy': 'milk',
  'carb': 'grain',
  'veg': 'leaf',
  'fruit': 'apple',
  'fat': 'avocado',
  'drink': 'cup',
  'other': 'meal',
};

class Foods {
  Foods._();

  static final Foods instance = Foods._();

  final List<Food> _db = [];
  final Map<String, Food> _index = {};
  List<String> _customIds = const [];

  List<Food> get db => List.unmodifiable(_db);

  bool get isLoaded => _db.isNotEmpty;

  Future<void> load() async {
    if (isLoaded) return;
    final raw = jsonDecode(await rootBundle.loadString('assets/data/foods.json')) as List;
    for (final e in raw) {
      final f = Food.fromJson(Map<String, dynamic>.from(e as Map));
      _db.add(f);
      _index[f.id] = f;
    }
  }

  /// Merges the profile's own foods into the id index, the way [Exercises.registerCustom]
  /// does, so one lookup serves both kinds everywhere.
  void registerCustom(List<CustomFood> list) {
    for (final id in _customIds) {
      _index.remove(id);
    }
    _customIds = [for (final c in list) c.id];
    for (final c in list) {
      _index[c.id] = Food.fromCustom(c);
    }
  }

  Food? operator [](String? id) => id == null ? null : _index[id];

  /// An id that resolves to nothing still has to render — a meal logged against a custom food
  /// since deleted, or a backup from a build with a larger catalogue.
  Food or(String id) => _index[id] ??
      Food(id: id, n: t('Unknown food'), cat: 'other', kcal: 0, p: 0, c: 0, f: 0, missing: true);

  /// The full searchable catalogue — the profile's own foods first, as the library does.
  List<Food> all(AppState s) => [for (final c in s.nutrition.foods) Food.fromCustom(c), ..._db];

  /// Protein sources, densest first — the "what kind of protein" question, answered.
  List<Food> proteinSources(AppState s) {
    final out = [for (final f in all(s)) if (f.p > 0) f]
      ..sort((a, b) => b.proteinDensity.compareTo(a.proteinDensity));
    return out;
  }

  /// Name search, in catalogue order. Matches on the translated name too, so searching in the
  /// language the app is displaying finds something.
  List<Food> search(AppState s, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return all(s);
    return [
      for (final f in all(s))
        if (f.n.toLowerCase().contains(q) || t(f.n).toLowerCase().contains(q)) f
    ];
  }
}

/// Short alias, matching `exdb`.
final foods = Foods.instance;

/// `by-sa-4.0` -> `CC BY-SA 4.0`. Public domain marks say so in words instead.
String _licenceName(String raw) {
  final parts = raw.split('-');
  final version = parts.isNotEmpty && RegExp(r'^\d').hasMatch(parts.last) ? parts.removeLast() : null;
  final code = parts.join('-').toUpperCase();
  if (code == 'CC0') return 'CC0 ${version ?? ''}'.trim();
  if (code == 'PDM') return 'Public domain';
  return 'CC $code${version == null ? '' : ' $version'}';
}
