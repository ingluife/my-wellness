import 'json.dart';

/// Everything the app needs to turn a training plan into a calorie and macro target, plus the
/// meals logged against it.
///
/// None of this exists in openGym. Its store carries no body metrics beyond weight and no food
/// log at all, so `nutrition` and `meals` are keys My Wellness adds. openGym loads its state with
/// `Object.assign(clone(DEF), JSON.parse(raw))` and persists the whole object, so both survive a
/// round trip through it untouched — they simply do not render there. That is only true while
/// this build keeps writing them *absently* until the feature is used; see AppState.toJson.

/// The body metrics an energy estimate needs, none of which the app collected before.
///
/// [sex] is deliberately not `AppState.body`. That field picks which figure the muscle map
/// draws and its doc comment says nothing else reads it; this one is an input to a formula.
/// Conflating a drawing preference with a biological parameter would mean switching the body
/// diagram silently rewrote the calorie target.
class BodyProfile {
  BodyProfile({this.age, this.height, this.sex, this.activity});

  /// Years.
  double? age;

  /// Centimetres, always — `AppState.unit` is a label on logged weights and never applies here.
  double? height;

  /// 'male' | 'female'. Mifflin-St Jeor has no third term; an unset value leaves [isComplete]
  /// false and every estimate null rather than guessing.
  String? sex;

  /// Non-exercise activity: 'sedentary' | 'light' | 'moderate' | 'active'.
  ///
  /// Only non-exercise, because training burn is added from the logged sessions. The usual
  /// 1.2-1.9 multipliers already fold exercise in, and using them here would count it twice.
  String? activity;

  /// Mifflin-St Jeor needs all three. Activity has a defensible fallback; these do not.
  bool get isComplete => age != null && height != null && sex != null;

  bool get isEmpty => age == null && height == null && sex == null && activity == null;

  factory BodyProfile.fromJson(Map<String, dynamic> j) => BodyProfile(
        age: asNum(j['age']),
        height: asNum(j['height']),
        sex: asStr(j['sex']),
        activity: asStr(j['activity']),
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    putNum(m, 'age', age);
    putNum(m, 'height', height);
    put(m, 'sex', sex);
    put(m, 'activity', activity);
    return m;
  }

  BodyProfile copy() => BodyProfile.fromJson(toJson());
}

/// What the target is aiming at.
///
/// Every field is nullable with a documented reading, rather than carrying a default value.
/// That follows `effort`: a profile that never chose has to stay distinguishable from one that
/// chose the value that happens to be the default, or the key can never be dropped again and
/// the state stops matching a fresh openGym export.
class NutritionGoal {
  NutritionGoal({this.mode, this.rate, this.kcal, this.protein, this.fatPct, this.meals});

  /// 'cut' | 'maintain' | 'gain'. null = never chosen, read as maintain.
  String? mode;

  /// Intended kg per week, signed. null = derive from [mode].
  double? rate;

  /// Manual overrides. Set only when the user has overruled the computed value, which is why
  /// they are absent rather than pre-filled — a stored copy of a derived number goes stale the
  /// moment body weight moves.
  double? kcal;
  double? protein;
  double? fatPct;

  /// Meals per day. null = never chosen, read as 4.
  double? meals;

  /// Which kitchen the day plan cooks from. null = never chosen, read from the UI language.
  ///
  /// Here rather than on [BodyProfile] because [meals] is the precedent: a field that shapes how
  /// the day is presented and never touches what the day has to add up to. Nothing downstream of
  /// this may reach the calorie target, or a preference about food becomes a change to the plan.
  String? cuisine;

  bool get isDefault =>
      mode == null &&
      rate == null &&
      kcal == null &&
      protein == null &&
      fatPct == null &&
      meals == null &&
      cuisine == null;

  factory NutritionGoal.fromJson(Map<String, dynamic> j) => NutritionGoal(
        mode: asStr(j['mode']),
        rate: asNum(j['rate']),
        kcal: asNum(j['kcal']),
        protein: asNum(j['protein']),
        fatPct: asNum(j['fatPct']),
        meals: asNum(j['meals']),
      )..cuisine = asStr(j['cuisine']);

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    put(m, 'mode', mode);
    putNum(m, 'rate', rate);
    putNum(m, 'kcal', kcal);
    putNum(m, 'protein', protein);
    putNum(m, 'fatPct', fatPct);
    putNum(m, 'meals', meals);
    put(m, 'cuisine', cuisine);
    return m;
  }

  NutritionGoal copy() => NutritionGoal.fromJson(toJson());
}

/// The `nutrition` key: the profile and the goal, and nothing derived.
///
/// There is no weekly nutrition schedule stored here on purpose. `AppState.week` and `dayPlan`
/// already say which days are training days, so a per-day target is a function of the plan the
/// user already set. A second copy of that schedule would go stale the first time a routine
/// moved to another day.
class Nutrition {
  Nutrition({
    BodyProfile? profile,
    NutritionGoal? goal,
    List<CustomFood>? foods,
    List<MealTemplate>? templates,
    this.dismissedAdj,
  })  : profile = profile ?? BodyProfile(),
        goal = goal ?? NutritionGoal(),
        foods = foods ?? [],
        templates = templates ?? [];

  BodyProfile profile;
  NutritionGoal goal;

  /// Meals saved for one-tap logging.
  List<MealTemplate> templates;

  /// When a suggested target adjustment was last turned down, as ms since epoch.
  ///
  /// Kept so the offer does not become nagging: a suggestion declined once should stay declined
  /// until either enough time has passed or the evidence has actually changed.
  int? dismissedAdj;

  /// Foods the user defined. Kept here rather than beside `customEx` at the top level so the
  /// whole feature stays inside one key that openGym can carry through as a unit.
  List<CustomFood> foods;

  /// Nothing has been set — the key is dropped entirely so a profile that never opened the
  /// feature still exports the same JSON openGym does.
  bool get isDefault =>
      profile.isEmpty &&
      goal.isDefault &&
      foods.isEmpty &&
      templates.isEmpty &&
      dismissedAdj == null;

  factory Nutrition.fromJson(Map<String, dynamic> j) => Nutrition(
        profile: j['profile'] is Map ? BodyProfile.fromJson(asMap(j['profile'])) : null,
        goal: j['goal'] is Map ? NutritionGoal.fromJson(asMap(j['goal'])) : null,
        foods: asList(j['foods'], CustomFood.fromJson),
        templates: asList(j['templates'], MealTemplate.fromJson),
        dismissedAdj: asNum(j['dismissedAdj'])?.toInt(),
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    final p = profile.toJson();
    final g = goal.toJson();
    if (p.isNotEmpty) m['profile'] = p;
    if (g.isNotEmpty) m['goal'] = g;
    if (foods.isNotEmpty) m['foods'] = [for (final f in foods) f.toJson()];
    if (templates.isNotEmpty) {
      m['templates'] = [for (final x in templates) x.toJson()];
    }
    put(m, 'dismissedAdj', dismissedAdj);
    return m;
  }

  Nutrition copy() => Nutrition.fromJson(toJson());
}

/// A food the user defined, for anything the bundled catalog does not carry.
///
/// Mirrors CustomExercise: a name and the numbers is all it takes, and it then behaves like a
/// catalog food everywhere, just without a photograph. Macros are per 100 g, like the catalog.
class CustomFood {
  CustomFood({
    required this.id,
    required this.n,
    this.cat = 'other',
    this.kcal = 0,
    this.p = 0,
    this.c = 0,
    this.f = 0,
    this.fib,
    this.sug,
    this.sat,
    this.salt,
  });

  final String id;
  String n;
  String cat;
  double kcal;
  double p;
  double c;
  double f;

  /// The rest of a nutrition label, per 100 g. Null, not zero — "not said" and "zero" are
  /// different answers, and only a value the user actually typed should ever reach the sheet.
  double? fib;
  double? sug;
  double? sat;
  double? salt;

  factory CustomFood.fromJson(Map<String, dynamic> j) => CustomFood(
        id: asStr(j['id']) ?? '',
        n: asStr(j['n']) ?? '',
        cat: asStr(j['cat']) ?? 'other',
        kcal: asNumOr(j['kcal'], 0),
        p: asNumOr(j['p'], 0),
        c: asNumOr(j['c'], 0),
        f: asNumOr(j['f'], 0),
        fib: asNum(j['fib']),
        sug: asNum(j['sug']),
        sat: asNum(j['sat']),
        salt: asNum(j['salt']),
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{
      'id': id,
      'n': n,
      'cat': cat,
      'kcal': jsonNum(kcal),
      'p': jsonNum(p),
      'c': jsonNum(c),
      'f': jsonNum(f),
      'custom': true,
    };
    putNum(m, 'fib', fib);
    putNum(m, 'sug', sug);
    putNum(m, 'sat', sat);
    putNum(m, 'salt', salt);
    return m;
  }

  CustomFood copy() => CustomFood.fromJson(toJson());
}

/// One food inside a meal, with its macros resolved at the moment it was logged.
///
/// The numbers are *stored*, not looked up from the catalog on read. `assets/data/foods.json`
/// is regenerated from USDA data by a script, and a regenerated catalog silently rewriting what
/// last month's log says you ate would make the history worthless. [fid] is kept so the entry
/// can still show a photograph and be re-added, but it is a reference, never the source of the
/// numbers.
class MealItem {
  MealItem({
    this.fid,
    this.n,
    required this.g,
    required this.kcal,
    required this.p,
    required this.c,
    required this.f,
  });

  /// Catalog or custom-food id. Absent for a one-off typed by hand.
  String? fid;

  /// Display name. Absent when [fid] resolves to one.
  String? n;

  /// Grams eaten.
  double g;

  double kcal;
  double p;
  double c;
  double f;

  factory MealItem.fromJson(Map<String, dynamic> j) => MealItem(
        fid: asStr(j['fid']),
        n: asStr(j['n']),
        g: asNumOr(j['g'], 0),
        kcal: asNumOr(j['kcal'], 0),
        p: asNumOr(j['p'], 0),
        c: asNumOr(j['c'], 0),
        f: asNumOr(j['f'], 0),
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    put(m, 'fid', fid);
    put(m, 'n', n);
    m['g'] = jsonNum(g);
    m['kcal'] = jsonNum(kcal);
    m['p'] = jsonNum(p);
    m['c'] = jsonNum(c);
    m['f'] = jsonNum(f);
    return m;
  }

  MealItem copy() => MealItem.fromJson(toJson());
}

/// A meal worth logging again — the user's own recipes.
///
/// Most people rotate ten to fifteen meals. Without this the app makes them rebuild each one
/// food by food every time, which is the single biggest reason a food log gets abandoned in
/// week one.
///
/// These are also the best thing the day planner has to offer. A bundled catalogue of dishes
/// can only ever guess at what somebody eats; this is the answer, written down by the person
/// who eats it, in their own words and their own language. [slot] and [servings] exist so the
/// planner can use one — it has to know when a recipe is eaten and what one portion of it is.
class MealTemplate {
  MealTemplate({
    required this.id,
    required this.n,
    List<MealItem>? items,
    this.slot,
    this.servings,
    this.used,
    this.last,
  }) : items = items ?? [];

  final String id;
  String n;
  List<MealItem> items;

  /// Which meal of the day this is, as an English slot name from `mealSplit` — 'Breakfast',
  /// 'Lunch', 'Snack', 'Dinner'. null = never chosen, and the planner reads it as "any".
  ///
  /// A name rather than the numeric index [Meal.slot] carries, and deliberately so: that index
  /// is a position in whatever meal split was current when it was written, and index 2 is a
  /// snack under a four-meal day and lunch under a six-meal one. A recipe outlives that setting.
  String? slot;

  /// How many portions [items] makes. null = never chosen, read as 1.
  ///
  /// The difference between a saved meal and a recipe. A stew is entered once, as the pot, and
  /// eaten a bowl at a time; without this the ingredient list has to be pre-divided by hand and
  /// re-entered whenever the batch size changes.
  double? servings;

  /// Times logged, and when it was last logged. Together they order the list by what the user
  /// actually eats, the way recent foods are already ordered.
  double? used;
  int? last;

  /// What the whole ingredient list comes to.
  double get batchKcal => items.fold(0, (a, i) => a + i.kcal);

  /// What one portion comes to — what the list, the log and the planner all read.
  double get kcal => batchKcal / perServing;
  double get p => items.fold<double>(0, (a, i) => a + i.p) / perServing;
  double get c => items.fold<double>(0, (a, i) => a + i.c) / perServing;
  double get f => items.fold<double>(0, (a, i) => a + i.f) / perServing;

  /// [servings], read. Guarded because a zero here would divide every macro into infinity, and
  /// the field is reachable from an imported or hand-edited state.
  double get perServing {
    final n = servings ?? 1;
    return n < 1 ? 1 : n;
  }

  /// One portion of this recipe, ready to log.
  List<MealItem> portion() {
    final n = perServing;
    return [
      for (final i in items)
        MealItem(
          fid: i.fid,
          n: i.n,
          g: i.g / n,
          kcal: i.kcal / n,
          p: i.p / n,
          c: i.c / n,
          f: i.f / n,
        )
    ];
  }

  factory MealTemplate.fromJson(Map<String, dynamic> j) => MealTemplate(
        id: asStr(j['id']) ?? '',
        n: asStr(j['n']) ?? '',
        items: asList(j['items'], MealItem.fromJson),
        slot: asStr(j['slot']),
        servings: asNum(j['servings']),
        used: asNum(j['used']),
        last: asNum(j['last'])?.toInt(),
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'id': id, 'n': n};
    m['items'] = [for (final i in items) i.toJson()];
    put(m, 'slot', slot);
    putNum(m, 'servings', servings);
    putNum(m, 'used', used);
    put(m, 'last', last);
    return m;
  }

  MealTemplate copy() => MealTemplate.fromJson(toJson());
}

/// One meal on one day. `d` is the day it counts against; `t` is the wall clock it was logged
/// at — the same split BodyWeightEntry uses, and for the same reason: a late dinner still
/// belongs to the day it was eaten on.
class Meal {
  Meal(
      {required this.id,
      required this.d,
      this.t,
      this.slot,
      this.photo,
      List<MealItem>? items})
      : items = items ?? [];

  final String id;
  String d;
  int? t;

  /// Which slot of the day, as an index into the plan's meal split. Absent means unassigned,
  /// which still counts towards the day's totals.
  double? slot;

  /// The photograph this meal was drafted from, as a **file name** — never a path.
  ///
  /// A path would be wrong within a week: the app's documents directory is re-created with a new
  /// container id on every iOS reinstall and restore, so an absolute path written today points at
  /// nothing tomorrow while looking perfectly valid. The name is resolved against whatever the
  /// directory happens to be now, by `MealPhotoStore`.
  ///
  /// Nothing depends on it. The file is decoration on a record that is complete without it: it is
  /// not in a backup, it is deleted after 90 days, and it is dropped the moment the file behind it
  /// is gone. Every reader has to treat a missing photo as ordinary, because it is.
  String? photo;

  List<MealItem> items;

  double get kcal => items.fold(0, (a, i) => a + i.kcal);
  double get p => items.fold(0, (a, i) => a + i.p);
  double get c => items.fold(0, (a, i) => a + i.c);
  double get f => items.fold(0, (a, i) => a + i.f);

  factory Meal.fromJson(Map<String, dynamic> j) => Meal(
        id: asStr(j['id']) ?? '',
        d: asStr(j['d']) ?? '',
        t: asNum(j['t'])?.toInt(),
        slot: asNum(j['slot']),
        photo: asStr(j['photo']),
        items: asList(j['items'], MealItem.fromJson),
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'id': id, 'd': d};
    put(m, 't', t);
    putNum(m, 'slot', slot);
    // Absent until there is one, the same contract `nutrition`, `meals` and `ai` follow at the top
    // level — a meal logged by hand serialises exactly as it did before this key existed.
    put(m, 'photo', photo);
    m['items'] = [for (final i in items) i.toJson()];
    return m;
  }

  Meal copy() => Meal.fromJson(toJson());
}
