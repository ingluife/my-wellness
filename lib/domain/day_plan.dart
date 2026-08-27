
import 'dart:math' as math;

import '../data/models/app_state.dart';
import 'day_plan_source.dart';
import 'dishes.dart';
import 'foods.dart';
import 'nutrition.dart';

/// Proposing a day's meals, so the target arrives with an answer attached.
///
/// The app already tells you to eat 2,270 calories with 160 g of protein. That is a correct
/// number and an empty page, and the page is the hard part. This builds a day that hits it,
/// out of food the user actually eats, so meal structure is taught by example rather than
/// asserted.
///
/// **A plan is an intention, not a record.** Nothing here writes to `AppState`, and nothing
/// here is persisted. The user logs each meal when they eat it, by tapping the meal. That is
/// not squeamishness: `evolution()` compares what the log predicted against what the scale did,
/// and it is the one thing in the app that tells someone whether these estimates run high or
/// low *for them*. If a plan nobody followed could land in the log, that comparison becomes
/// noise and the most honest feature here becomes the least reliable.

/// One proposed meal. [items] are ready to hand to `addMealItem` unchanged.
///
/// [dish] is what the meal is *called* when it came from somewhere that had a name for it — one
/// of the user's own recipes, or a habit the log recognised. Null when the meal was assembled a
/// category at a time and there is honestly nothing to call it. A plain string rather than a
/// reference so the sheet never has to know where a proposal came from, and so a recipe's name
/// can go through in the user's own words without passing through translation.
typedef PlannedMeal = ({
  String name,
  String? dish,
  double slot,
  List<MealItem> items,
  Macros macros,
});

/// The default floor for a single food in a single meal. Below this the plan stops reading like
/// food and starts reading like a spreadsheet solving for protein.
const _minGrams = 30.0;

/// The most of a food that belongs on one plate, read off its energy density.
///
/// A single global ceiling was the bug that made this feature unusable: sized to carry a whole
/// breakfast's protein, Brie came out at 240 g, and 350 g was the only thing standing in the
/// way. A per-*category* ceiling cannot fix it either, because `dairy` holds both Brie at 334
/// kcal and skim milk at 35, and the number that is sane for one is absurd for the other.
///
/// Density is exactly the axis those two differ on, and it is already in the catalogue. It also
/// happens to be how portions work in a kitchen: what you spread, what you serve, what you fill
/// a plate with.
double _ceilingFor(Food f) => switch (f.kcal) {
      >= 600 => 30, // oils, butter, nut butters — a spoonful
      >= 350 => 60, // hard cheese, nuts, dried fruit — a handful
      >= 200 => 180, // bread, cured meat, grain by dry weight
      >= 80 => 300, // cooked grains, lean meat, fish — the body of a meal
      _ => 250, // vegetables, fruit, milk, drinks
    };

/// The floor, which cannot be a constant for the same reason the ceiling cannot.
///
/// 30 g of olive oil is not a minimum, it is four times a serving. Half the ceiling is the
/// smallest amount worth naming for anything the ceiling has already called small.
double _floorFor(Food f) => math.min(_minGrams, _ceilingFor(f) / 2);

/// How far a computed weight may be nudged to land on a household portion.
///
/// Generous on purpose: "1 chicken breast" is a better instruction than "173 g" even when it
/// costs 40 g of precision, and the precision was never real — the MET table and the portion
/// the user eyeballs are both worth more error than this.
const _snapTolerance = 0.35;

/// Foods worth proposing from, split into the user's own and everything else.
///
/// Two lists rather than one concatenated one, because the seed rotates *within* a list: a
/// single list with the user's food at the front would have the shuffle step straight past it,
/// which is exactly the bug this shape exists to prevent. A plan built from food someone has
/// never bought is a plan they will not follow.
({List<Food> mine, List<Food> rest}) _pool(AppState s, String cat) {
  final own = <String>{
    for (final tpl in s.nutrition.templates)
      for (final i in tpl.items)
        if (i.fid != null) i.fid!,
    for (final m in s.meals.reversed.take(40))
      for (final i in m.items)
        if (i.fid != null) i.fid!,
  };

  final mine = <Food>[];
  final rest = <Food>[];
  for (final f in foods.all(s)) {
    if (f.cat != cat || f.kcal <= 0) continue;
    (own.contains(f.id) ? mine : rest).add(f);
  }
  return (mine: mine, rest: rest);
}

/// The user's own foods first, the catalogue only once those are spent.
///
/// The seed rotates inside each group, so shuffling reaches a different one of *their* foods
/// before it reaches for a stranger's.
Food? _pick(({List<Food> mine, List<Food> rest}) pool, int seed, Set<String> used) {
  for (final group in [pool.mine, pool.rest]) {
    for (var i = 0; i < group.length; i++) {
      final candidate = group[(seed + i) % group.length];
      if (!used.contains(candidate.id)) return candidate;
    }
  }
  // Everything is spent — repeating a food beats returning an empty meal.
  final all = [...pool.mine, ...pool.rest];
  return all.isEmpty ? null : all[seed % all.length];
}

/// Two pools joined for the slots that draw on both, keeping each side's own/rest split.
({List<Food> mine, List<Food> rest}) _merge(
  ({List<Food> mine, List<Food> rest}) a,
  ({List<Food> mine, List<Food> rest}) b,
) =>
    (mine: [...a.mine, ...b.mine], rest: [...a.rest, ...b.rest]);

/// A pool narrowed to the foods [keep] accepts, on both sides of the split.
({List<Food> mine, List<Food> rest}) _where(
  ({List<Food> mine, List<Food> rest}) p,
  bool Function(Food) keep,
) =>
    (mine: p.mine.where(keep).toList(), rest: p.rest.where(keep).toList());

/// A pool reordered by protein per calorie, densest first.
///
/// Used for the dairy the breakfast slot draws on, and it is worth saying why. `_pick` rotates
/// from the front of a list, so at seed 0 the anchor is whatever sorts first in the catalogue —
/// which for `dairy` is Brie, purely because the catalogue happens to be alphabetical. Half of
/// "240 g of Brie for breakfast" was that accident rather than any decision.
///
/// Density is the fix rather than a hand-picked order, because it is the same question the food
/// library already answers with it: what a meal can be built on, as against what is spread on
/// top of one. Egg white, Greek yogurt and cottage cheese come to the front; Brie, cream cheese
/// and heavy cream go to the back where a garnish belongs.
({List<Food> mine, List<Food> rest}) _byDensity(({List<Food> mine, List<Food> rest}) p) {
  int denser(Food a, Food b) => b.proteinDensity.compareTo(a.proteinDensity);
  return (
    mine: [...p.mine]..sort(denser),
    rest: [...p.rest]..sort(denser),
  );
}

/// Snaps [grams] onto a household portion when one is close enough.
///
/// Bounded by the food's own band rather than a global one, because the snap used to make the
/// sizing bug *worse* instead of softening it: USDA files Brie with `cup, melted = 240 g`, and
/// multiplying that by four put 960 g within reach of a 35% tolerance. A measure that overshoots
/// what belongs on a plate is not a better instruction than the arithmetic it replaced.
double _snap(Food food, double grams) {
  final floor = _floorFor(food);
  final ceiling = _ceilingFor(food);

  var best = grams;
  var bestGap = double.infinity;
  for (final p in food.portions) {
    // Whole multiples too, so two eggs and three slices of bread are reachable.
    for (final n in const [1, 2, 3, 4]) {
      final g = p.g * n;
      if (g < floor || g > ceiling) continue;
      final gap = (g - grams).abs();
      if (gap < bestGap) {
        bestGap = gap;
        best = g;
      }
    }
  }
  if (bestGap <= grams * _snapTolerance) return best;

  // Nothing close: a round number still reads better than 173 — but the step has to scale with
  // the food. Rounding olive oil to the nearest 10 g turns a teaspoon into a lie.
  final step = ceiling <= 40
      ? 1.0
      : ceiling <= 100
          ? 5.0
          : 10.0;
  return ((grams / step).round() * step).clamp(floor, ceiling);
}

/// Grams of [food] carrying [kcal] calories.
double _gramsForKcal(Food food, double kcal) => kcal / food.kcal * 100;

/// Grams of [food] carrying [protein] grams of protein.
double _gramsForProtein(Food food, double protein) =>
    food.p <= 0 ? _minGrams : protein / food.p * 100;

/// What one food may weigh here: what the macro asks for, capped by what the meal can spend.
///
/// [wantGrams] is what the macro arithmetic asks for and is the reason a single item used to
/// become the whole meal — sizing the anchor to carry a slot's *entire* protein share produced
/// a 795 kcal breakfast of nothing but Feta. [kcalShare] is the fraction of the slot this item
/// is allowed to be, which turns "enough protein" into "enough protein, if the meal can afford
/// it" and leaves room for the rest of the plate.
double _size(
  Food food, {
  required double wantGrams,
  required double slotKcal,
  required double kcalShare,
}) =>
    math
        .min(wantGrams, _gramsForKcal(food, slotKcal * kcalShare))
        .clamp(_floorFor(food), _ceilingFor(food));

/// The most of a slot any one item may be, by role.
///
/// These are what keep a meal a meal. Without them the anchor takes whatever the protein target
/// asks for and the plate has nothing left to hold.
const _anchorShare = 0.50;
const _carbShare = 0.55;
const _fillerShare = 0.35;

/// The share of a slot a drink is allowed to be.
///
/// Small on purpose. Coffee is free and this never binds on it; the number exists so that orange
/// juice and milk arrive as a glass rather than as a way of paying for the meal.
const _drinkShare = 0.12;

/// The most things one meal may be made of.
///
/// A plate has a handful of things on it. Past that the suggestion stops being a meal somebody
/// could picture and becomes a shopping list that happens to add up.
const _maxItems = 6;

/// How far a slot may borrow from what the last one left on the table, as a fraction of itself.
///
/// Every item now has a ceiling, and ceilings mean a slot can come up short through no fault of
/// the arithmetic — a 350 kcal snack cannot be built out of foods that each cap at 60 g. Without
/// somewhere for that shortfall to go, the day quietly lands under target and the whole plan
/// stops being an example of hitting it. Bounded so one awkward slot cannot distort the next.
const _carryLimit = 0.15;

/// The slots that come with something to drink.
///
/// English source strings, matching `mealSplit`. Nobody has coffee with dinner and everybody has
/// it with breakfast, and until this the `drink` category was unreachable from the planner
/// entirely — eleven foods, coffee and tea among them, that it could never propose.
bool _takesADrink(String slot) => slot == 'Breakfast' || slot == 'Snack';

/// What a drink is poured at: its own household measure, or a glass.
///
/// Sized from the portion rather than from calories, because that is what a drink is. Deriving
/// it from an energy share would ask for four litres of coffee.
double _drinkGrams(Food f) => f.portions.isEmpty ? 200 : f.portions.first.g;

/// The most a drink may carry per 100 g and still be offered without being asked for.
///
/// The `drink` category holds coffee and tea at 1 kcal alongside cola at 42, beer at 43 and wine
/// at 85. A drink that comes with a meal is one thing; a drink that *is* a meal's worth of sugar
/// or alcohol is a decision, and a plan that proposes a beer with the afternoon snack because the
/// arithmetic had room for one has stopped being advice. Anything above this the user can still
/// log — it simply is not suggested.
const _drinkKcalMax = 35.0;

/// The first candidate in [group] that can be made to fit, rotated by [salt].
///
/// Rotation mirrors `_pick`: the seed walks the list rather than picking from it at random, so
/// the same seed always proposes the same day and "show me another" is a reshuffle rather than
/// a dice roll.
FittedMeal? _tryGroup(
  List<PlanCandidate> group, {
  required int salt,
  required double slotKcal,
  required double slotProtein,
  required Set<String> used,
}) {
  final eligible = [for (final c in group) if (!used.contains(c.name)) c];
  for (var i = 0; i < eligible.length; i++) {
    final candidate = eligible[(salt + i) % eligible.length];
    final fitted = fitToSlot(candidate, slotKcal: slotKcal, slotProtein: slotProtein);
    if (fitted != null) return fitted;
  }
  return null;
}

/// A named meal for this slot, resized to fit it — or null if nothing does.
///
/// Four groups, tried in order, and the seed rotates *within* a group rather than across the
/// four. That is the same shape `_pool` uses in this file and it exists for the same reason: a
/// single concatenated list with the good stuff at the front has the shuffle step straight past
/// it, which is exactly the bug the split prevents.
///
///   1. the user's own recipes and repeated meals — always better than anything bundled
///   2. bundled dishes from their kitchen
///   3. bundled dishes that belong to no kitchen in particular
///   4. bundled dishes from somebody else's kitchen
///
/// A user candidate filed under no slot competes everywhere, because "any meal" is what they
/// chose by leaving it unset.
FittedMeal? _pickMeal(
  List<PlanCandidate> recipes,
  String cuisine, {
  required String slot,
  required int salt,
  required double slotKcal,
  required double slotProtein,
  required Set<String> used,
}) {
  final groups = <List<PlanCandidate>>[
    [for (final c in recipes) if (c.slot == null || c.slot == slot) c],
  ];

  if (dishes.isLoaded) {
    final bundled = dishes.forSlot(slot, cuisine: cuisine);
    groups.addAll([
      [for (final d in bundled.mine) d.candidate],
      [for (final d in bundled.plain) d.candidate],
      [for (final d in bundled.rest) d.candidate],
    ]);
  }

  for (final group in groups) {
    final fitted = _tryGroup(
      group,
      salt: salt,
      slotKcal: slotKcal,
      slotProtein: slotProtein,
      used: used,
    );
    if (fitted != null) return fitted;
  }
  return null;
}

/// A day's meals, hitting the target for [iso] as closely as whole foods allow.
///
/// Greedy and deterministic: the same state and seed always produce the same day, which is what
/// makes "use a different one" a reshuffle rather than a dice roll, and what makes this
/// testable at all.
///
/// Per meal, in order: a protein anchor sized to the slot's share of the protein target, a
/// carbohydrate sized to most of what calories remain, something to finish the plate, and — if
/// the slot is still short — one more thing to close it. Protein leads because it is the macro
/// with a floor worth defending; carbohydrate follows because it is the cheapest way to buy the
/// calories back.
///
/// Every item is bounded by [_size] and [_ceilingFor], so no single food can become the meal.
/// The cost of that is slots that fall short, which is what [_carryLimit] is for.
List<PlannedMeal> buildDayPlan(AppState s, String iso, {int seed = 0}) {
  final target = macroTargets(s, iso: iso);
  if (target == null) return const [];

  final split = mealSplit(s.nutrition.goal);
  final proteins = _pool(s, 'protein');
  final dairy = _pool(s, 'dairy');
  final carbs = _pool(s, 'carb');
  final veg = _pool(s, 'veg');
  final fruit = _pool(s, 'fruit');
  final fats = _pool(s, 'fat');
  final drinks = _where(_pool(s, 'drink'), (f) => f.kcal <= _drinkKcalMax);

  // Fruit and starch, and deliberately not vegetables. An earlier version let the closer reach
  // for whatever was cheapest per calorie and it answered a 200 kcal gap with 336 g of lemon —
  // the same absurdity as the Brie, wearing a different hat. These two are the only categories
  // that can buy calories in a way that still reads as food.
  final closers = _merge(fruit, carbs);

  // What the user has told the app they eat, which is always a better proposal than anything
  // assembled out of categories — see `day_plan_source.dart`.
  final recipes = userCandidates(s);
  final cuisine = cuisineOf(s);

  final used = <String>{};

  /// Recipes already proposed today, by name. A day that suggests the same sandwich twice has
  /// stopped being a plan.
  final usedDishes = <String>{};

  final out = <PlannedMeal>[];

  var carry = 0.0;

  for (var i = 0; i < split.length; i++) {
    final (name, share) = split[i];
    final baseKcal = target.kcal * share;
    final slotKcal =
        baseKcal + carry.clamp(-baseKcal * _carryLimit, baseKcal * _carryLimit);
    final slotProtein = target.p * share;
    final items = <MealItem>[];
    final salt = seed * 7 + i * 3;

    // A meal with a name, if one fits this slot: the user's own first, then the catalogue.
    // Rotated by the seed the same way the food pools are, and for the same reason —
    // reshuffling has to reach a different one of *their* meals before it reaches for anything
    // the app made up.
    final fitted = _pickMeal(
      recipes,
      cuisine,
      slot: name,
      salt: salt,
      slotKcal: slotKcal,
      slotProtein: slotProtein,
      used: usedDishes,
    );
    if (fitted != null) {
      usedDishes.add(fitted.name);
      for (final item in fitted.items) {
        if (item.fid case final fid?) used.add(fid);
      }
      out.add((
        name: name,
        dish: fitted.name,
        slot: i.toDouble(),
        items: fitted.items,
        macros: fitted.macros,
      ));
      carry = slotKcal - fitted.macros.kcal;
      continue;
    }

    double spent() => items.fold(0.0, (a, x) => a + x.kcal);

    void take(Food food, double wantGrams, double kcalShare) {
      used.add(food.id);
      items.add(food.portion(_snap(
        food,
        _size(food, wantGrams: wantGrams, slotKcal: slotKcal, kcalShare: kcalShare),
      )));
    }

    // Breakfast leans on dairy and eggs the way breakfast actually does; the rest lean on meat
    // and fish. A plan proposing grilled chicken at 7am is technically correct and ignored.
    final proteinPool = i == 0 ? _merge(_byDensity(dairy), proteins) : proteins;
    final protein = _pick(proteinPool, salt, used);
    if (protein != null) {
      take(protein, _gramsForProtein(protein, slotProtein), _anchorShare);
    }

    // Something to drink, where the slot has one. Poured before the gap is measured so a glass
    // of juice counts against the meal instead of arriving on top of a finished one.
    if (_takesADrink(name)) {
      final drink = _pick(drinks, salt, used);
      if (drink != null) take(drink, _drinkGrams(drink), _drinkShare);
    }

    var left = slotKcal - spent();

    // Most of what is left goes to carbohydrate, which is where the calories are cheapest.
    if (left > 80) {
      final carb = _pick(carbs, salt, used);
      if (carb != null) {
        take(carb, _gramsForKcal(carb, left * 0.7), _carbShare);
        left = slotKcal - spent();
      }
    }

    // Then something to finish it: vegetables at the main meals, fruit or fat elsewhere.
    //
    // Breakfast is a main meal by share and still takes fruit, because the share test alone was
    // putting artichoke and brussels sprouts on the plate at seven in the morning — correct by
    // calories and the sort of suggestion that gets a feature ignored.
    if (left > 40) {
      final fillerPool = i > 0 && share >= 0.25 ? veg : (i.isEven ? fruit : fats);
      final filler = _pick(fillerPool, salt, used);
      if (filler != null) {
        take(filler, _gramsForKcal(filler, left), _fillerShare);
        left = slotKcal - spent();
      }
    }

    // Still a real gap after three things: add another, rather than stretching what is already
    // there past what a portion of it looks like.
    //
    // A loop rather than a single pass, because how many components a meal needs depends on how
    // big it is. Two meals a day means a 1,250 kcal lunch, and four capped items cannot reach
    // that however they are sized — the day used to land 700 kcal short. [_maxItems] is what
    // stops the other end, where a large slot turns into a list.
    while (left > 60 && items.length < _maxItems) {
      final closer = _pick(closers, salt, used);
      if (closer == null) break;
      take(closer, _gramsForKcal(closer, left), _fillerShare);
      left = slotKcal - spent();
    }

    // What this slot could not spend is offered to the next one.
    carry = left;

    out.add((
      name: name,
      dish: null,
      slot: i.toDouble(),
      items: items,
      macros: (
        kcal: spent(),
        p: items.fold(0.0, (a, x) => a + x.p),
        c: items.fold(0.0, (a, x) => a + x.c),
        f: items.fold(0.0, (a, x) => a + x.f),
      ),
    ));
  }

  return out;
}

/// What a whole proposed day comes to.
Macros dayPlanTotals(List<PlannedMeal> plan) => (
      kcal: plan.fold(0.0, (a, m) => a + m.macros.kcal),
      p: plan.fold(0.0, (a, m) => a + m.macros.p),
      c: plan.fold(0.0, (a, m) => a + m.macros.c),
      f: plan.fold(0.0, (a, m) => a + m.macros.f),
    );
