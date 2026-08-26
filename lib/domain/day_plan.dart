
import '../data/models/app_state.dart';
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
typedef PlannedMeal = ({
  String name,
  double slot,
  List<MealItem> items,
  Macros macros,
});

/// Sensible bounds for a single food in a single meal. Outside these the plan stops reading
/// like food and starts reading like a spreadsheet solving for protein.
const _minGrams = 30.0;
const _maxGrams = 350.0;

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

/// Snaps [grams] onto a household portion when one is close enough.
double _snap(Food food, double grams) {
  var best = grams;
  var bestGap = double.infinity;
  for (final p in food.portions) {
    // Whole multiples too, so two eggs and three slices of bread are reachable.
    for (final n in const [1, 2, 3, 4]) {
      final g = p.g * n;
      if (g < _minGrams || g > _maxGrams) continue;
      final gap = (g - grams).abs();
      if (gap < bestGap) {
        bestGap = gap;
        best = g;
      }
    }
  }
  if (bestGap <= grams * _snapTolerance) return best;
  // Nothing close: a round number still reads better than 173.
  return (grams / 10).round() * 10;
}

/// Grams of [food] carrying [kcal] calories, kept inside plausible bounds.
double _gramsForKcal(Food food, double kcal) =>
    (kcal / food.kcal * 100).clamp(_minGrams, _maxGrams);

/// Grams of [food] carrying [protein] grams of protein.
double _gramsForProtein(Food food, double protein) =>
    food.p <= 0 ? _minGrams : (protein / food.p * 100).clamp(_minGrams, _maxGrams);

/// A day's meals, hitting the target for [iso] as closely as whole foods allow.
///
/// Greedy and deterministic: the same state and seed always produce the same day, which is what
/// makes "use a different one" a reshuffle rather than a dice roll, and what makes this
/// testable at all.
///
/// Per meal, in order: a protein anchor sized to the slot's share of the protein target, a
/// carbohydrate sized to most of what calories remain, and something to close the gap. Protein
/// leads because it is the macro with a floor worth defending; carbohydrate follows because it
/// is the cheapest way to buy the calories back.
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

  final used = <String>{};
  final out = <PlannedMeal>[];

  for (var i = 0; i < split.length; i++) {
    final (name, share) = split[i];
    final slotKcal = target.kcal * share;
    final slotProtein = target.p * share;
    final items = <MealItem>[];
    final salt = seed * 7 + i * 3;

    // Breakfast leans on dairy and eggs the way breakfast actually does; the rest lean on meat
    // and fish. A plan proposing grilled chicken at 7am is technically correct and ignored.
    final proteinPool = i == 0 ? _merge(dairy, proteins) : proteins;
    final protein = _pick(proteinPool, salt, used);
    if (protein != null) {
      used.add(protein.id);
      final grams = _snap(protein, _gramsForProtein(protein, slotProtein));
      items.add(protein.portion(grams));
    }

    var left = slotKcal - items.fold(0.0, (a, x) => a + x.kcal);

    // Most of what is left goes to carbohydrate, which is where the calories are cheapest.
    if (left > 80) {
      final carb = _pick(carbs, salt, used);
      if (carb != null) {
        used.add(carb.id);
        final grams = _snap(carb, _gramsForKcal(carb, left * 0.7));
        items.add(carb.portion(grams));
        left = slotKcal - items.fold(0.0, (a, x) => a + x.kcal);
      }
    }

    // Then something to finish it: vegetables at the main meals, fruit or fat elsewhere.
    if (left > 40) {
      final fillerPool = share >= 0.25 ? veg : (i.isEven ? fruit : fats);
      final filler = _pick(fillerPool, salt, used);
      if (filler != null) {
        used.add(filler.id);
        final grams = _snap(filler, _gramsForKcal(filler, left));
        items.add(filler.portion(grams));
      }
    }

    out.add((
      name: name,
      slot: i.toDouble(),
      items: items,
      macros: (
        kcal: items.fold(0.0, (a, x) => a + x.kcal),
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
