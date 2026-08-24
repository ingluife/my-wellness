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
      );

  factory Food.fromCustom(CustomFood c) => Food(
        id: c.id,
        n: c.n,
        cat: c.cat,
        kcal: c.kcal,
        p: c.p,
        c: c.c,
        f: c.f,
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
}

/// The catalogue order the library browses in, and the order category chips appear in:
/// what a lifter is looking for first.
const foodCategories = <String>[
  'protein', 'dairy', 'carb', 'veg', 'fruit', 'fat', 'drink',
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
