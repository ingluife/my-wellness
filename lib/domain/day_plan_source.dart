import 'dart:math' as math;

import '../data/models/app_state.dart';
import 'foods.dart';
import 'i18n.dart';
import 'nutrition.dart';

/// Where a proposed meal comes from, and how it is resized to fit a slot.
///
/// The day planner used to assemble a meal one category at a time: a protein, a carbohydrate,
/// something green. That is how you hit a macro target and it is not how anybody eats. Nothing
/// in it knew that bread, ham and cheese are a sandwich while bread, brie and broccoli are
/// three ingredients on a table.
///
/// This is the other half of the answer. The user has already written down what they eat —
/// every saved recipe, and every meal they have logged the same way three times — and those are
/// better than any catalogue of dishes could be, because they are in the user's own words, in
/// the user's own language, made of food the user actually buys. What was missing was a way to
/// take one of them and make it fit *this* slot on *this* day, which is what the roles below do.
///
/// Nothing here writes to [AppState], and it must stay that way; see the note at the top of
/// `day_plan.dart` for why that invariant is worth more than it looks.

/// How far one component of a meal may move when the meal is scaled.
///
/// A dish scaled by multiplying everything is a bigger dish; a dish scaled by stretching one
/// ingredient is a different dish, and usually a worse one. The roles are the difference. They
/// are also the structural answer to the bug that started all this: cheese enters a meal as an
/// [accent], and an accent is capped at twice what the recipe says, so 240 g of Brie is not
/// something the planner can propose because it is not something it can represent.
enum PartRole {
  /// The cup of coffee, the splash of milk in it. Never moves.
  fixed,

  /// Slices of bread, eggs, tortillas. Whole units of [MealPart.step] — two slices or three,
  /// never 2.4.
  unit,

  /// The anchor, and where protein is bought.
  flex,

  /// The cheese, the olives, the anchovies. Something you have a piece of.
  accent,

  /// The salad, the vegetables. The energy sink of last resort.
  side,

  /// Oil, butter, mayonnaise.
  trace,
}

/// What each role may be multiplied by, and what its grams round to.
const _bands = <PartRole, ({double min, double max, double round})>{
  PartRole.fixed: (min: 1, max: 1, round: 1),
  PartRole.unit: (min: 1, max: 3, round: 1),
  PartRole.flex: (min: 0.6, max: 1.8, round: 5),
  PartRole.accent: (min: 0.5, max: 2, round: 1),
  PartRole.side: (min: 0.5, max: 2, round: 10),
  PartRole.trace: (min: 0, max: 1.5, round: 1),
};

/// One component of a proposed meal, at the size the recipe writes it down as.
///
/// [base] carries its own macros, and every resize is computed from those rather than from a
/// catalogue lookup. That is not fussiness: `MealItem` stores its numbers precisely so that
/// regenerating `foods.json` cannot rewrite what last month's log says you ate, and it is also
/// the only thing that lets a quick-added or custom food be scaled at all.
typedef MealPart = ({MealItem base, PartRole role, double? step});

/// A meal the planner could propose, before it has been fitted to anything.
typedef PlanCandidate = ({String name, String? slot, List<MealPart> parts});

/// A candidate resized to a slot, with how badly it fits.
typedef FittedMeal = ({String name, List<MealItem> items, Macros macros, double score});

/// [base] resized to [grams], macros and all.
MealItem _at(MealItem base, double grams) {
  // A quick-added entry has calories and no weight. There is nothing to scale by, so it is
  // taken as it stands — which is also why the role table calls those `fixed`.
  if (base.g <= 0) return base.copy();
  final k = grams / base.g;
  return MealItem(
    fid: base.fid,
    n: base.n,
    g: grams,
    kcal: base.kcal * k,
    p: base.p * k,
    c: base.c * k,
    f: base.f * k,
  );
}

/// [part] at [factor] times its recipe size, kept inside its role's band and rounded to it.
MealItem _scaled(MealPart part, double factor) {
  final band = _bands[part.role]!;
  final k = factor.clamp(band.min, band.max);

  if (part.role == PartRole.unit || part.role == PartRole.accent) {
    final step = part.step ?? part.base.g;
    if (step > 0) {
      final units = (part.base.g * k / step).round().clamp(
            math.max(1, (band.min * part.base.g / step).floor()),
            math.max(1, (band.max * part.base.g / step).ceil()),
          );
      return _at(part.base, step * units);
    }
  }

  final grams = part.base.g * k;
  final step = band.round;
  // A trace may round to nothing, which is correct — no oil is a real answer. Everything else
  // keeps at least one step, because a part of a dish that rounds away stops being the dish.
  final rounded = (grams / step).round() * step;
  return _at(part.base, part.role == PartRole.trace ? rounded : math.max(step, rounded));
}

Macros _totals(List<MealItem> items) => (
      kcal: items.fold(0.0, (a, x) => a + x.kcal),
      p: items.fold(0.0, (a, x) => a + x.p),
      c: items.fold(0.0, (a, x) => a + x.c),
      f: items.fold(0.0, (a, x) => a + x.f),
    );

/// How much a per-slot protein shortfall counts against a meal, next to a calorie miss.
///
/// Less than calories, and that is a position rather than a fudge. `mealSplit` says outright
/// that the splits are conventional rather than optimal, because total intake and total protein
/// are what move body composition and meal timing is a rounding error beside them. Scoring
/// protein per slot as heavily as calories contradicts that, and it does real damage: porridge
/// with milk and a banana is a breakfast millions of people eat, and at full weight it is
/// rejected for not carrying a quarter of the day's protein by nine in the morning. A slot that
/// runs light is a slot the rest of the day pays for — exactly what the calorie carry in
/// `day_plan.dart` already assumes.
const _proteinWeight = 0.5;

/// How badly a fitted meal misses the slot, as one number.
///
/// Calories count in both directions; protein counts only when it falls short, because coming
/// in over the protein target is not a fault. This is also what makes slot-appropriateness fall
/// out rather than needing rules: a 900 kcal dinner scored against a 10% snack fails the calorie
/// term at the far end of its band and is never offered, with nobody having had to write down
/// that paella is not a snack.
double _score(Macros got, double slotKcal, double slotProtein) {
  final kcal = slotKcal <= 0 ? 0.0 : (got.kcal - slotKcal).abs() / slotKcal;
  final protein =
      slotProtein <= 0 ? 0.0 : math.max(0.0, (slotProtein - got.p) / slotProtein);
  return kcal + protein * _proteinWeight;
}

/// How far off the slot's calories a meal may land and still be offered.
///
/// This is the whole acceptance test, and it is what makes slot-appropriateness fall out of the
/// arithmetic rather than needing rules: a 1,400 kcal dinner scored against a 230 kcal snack
/// cannot be shrunk into range, so it is never offered there, and nobody had to write down that
/// a roast is not a snack.
const _kcalLimit = 0.30;

/// How far a candidate's own size may be from the slot before scaling is asked to do too much.
///
/// A recipe stretched past this stops being the recipe. Asymmetric because shrinking a meal
/// reads worse than growing one: half a portion of something is visibly half a portion.
const _tooSmall = 0.55;
const _tooBig = 1.8;

/// [candidate] fitted to a slot, or null if it cannot be made to fit.
///
/// Two passes. The first scales every part together, which is the whole point — a dish stays
/// recognisably itself only if its components move as one. The second repairs what the bands
/// clipped, one step at a time, and is bounded so that termination is a matter of reading the
/// loop rather than trusting it.
FittedMeal? fitToSlot(PlanCandidate candidate, {
  required double slotKcal,
  required double slotProtein,
}) {
  if (candidate.parts.isEmpty || slotKcal <= 0) return null;

  final reference = _totals([for (final p in candidate.parts) p.base]);
  if (reference.kcal <= 0) return null;

  final factor = slotKcal / reference.kcal;
  if (factor < _tooSmall || factor > _tooBig) return null;

  final items = [for (final p in candidate.parts) _scaled(p, factor)];
  var totals = _totals(items);

  // Pass two: nudge one part by one step, whichever move improves the fit most, until none
  // does. A hill climb rather than the obvious rule — "short of protein, grow the protein" —
  // because that rule is wrong in a way that only shows up on real meals. Porridge, milk and a
  // banana is short of a quarter of the day's protein however it is scaled, so the rule grew
  // the oats every round until breakfast was 155 g of them and 897 kcal: it fixed nothing and
  // wrecked the calories on the way. Requiring each step to lower the score cannot do that, and
  // it terminates for free, since the score strictly decreases.
  for (var round = 0; round < 6; round++) {
    var best = _score(totals, slotKcal, slotProtein);
    int? bestPart;
    double? bestGrams;

    for (var i = 0; i < candidate.parts.length; i++) {
      final part = candidate.parts[i];
      if (part.role == PartRole.fixed || part.base.g <= 0) continue;
      final band = _bands[part.role]!;
      final step = part.role == PartRole.unit || part.role == PartRole.accent
          ? (part.step ?? part.base.g)
          : band.round;

      for (final direction in const [1.0, -1.0]) {
        final next = items[i].g + step * direction;
        if (next <= 0) continue;
        if (next < part.base.g * band.min - 1e-9) continue;
        if (next > part.base.g * band.max + 1e-9) continue;

        final trial = [...items]..[i] = _at(part.base, next);
        final score = _score(_totals(trial), slotKcal, slotProtein);
        if (score < best - 1e-9) {
          best = score;
          bestPart = i;
          bestGrams = next;
        }
      }
    }

    if (bestPart == null) break;
    items[bestPart] = _at(candidate.parts[bestPart].base, bestGrams!);
    totals = _totals(items);
  }

  // Accepted on how well it fits the *size* of the slot, not on its macro split. A meal the
  // user actually eats has already earned its place; what the planner is deciding is whether
  // this is the slot it belongs in. Rejecting a real breakfast for carrying too little protein
  // by nine in the morning would throw away the whole point of asking them.
  if ((totals.kcal - slotKcal).abs() / slotKcal > _kcalLimit) return null;

  return (
    name: candidate.name,
    items: items,
    macros: totals,
    score: _score(totals, slotKcal, slotProtein),
  );
}

/// Which meal of the day a bucket of logged meals belongs to.
String _bucketOf(int ms) {
  final hour = DateTime.fromMillisecondsSinceEpoch(ms).hour;
  if (hour < 11) return 'Breakfast';
  if (hour < 16) return 'Lunch';
  if (hour < 19) return 'Snack';
  return 'Dinner';
}

/// When a meal with this [signature] is actually eaten, or null if the log cannot say.
///
/// The wall clock is asked first and it is the robust answer: `addMealItem` stamps `Meal.t` on
/// everything logged in the app, so the modal hour across every time this meal was eaten is a
/// direct observation rather than an inference.
///
/// `Meal.slot` is the fallback and is never compared as a number. It is an index into whatever
/// meal split was current when it was written, and index 2 is a snack under a four-meal day and
/// lunch under a six-meal one — so it is resolved to a *name* through today's split first. A
/// user who has changed their meal count has some mislabelled history; the cost of that is a
/// suggestion in the wrong slot, which is worth far less than the cost of guessing.
String? inferSlot(AppState s, String signature) {
  final matches = [for (final m in s.meals) if (signatureOf(m.items) == signature) m];
  if (matches.isEmpty) return null;

  final byHour = <String, int>{};
  for (final m in matches) {
    if (m.t case final ms?) byHour[_bucketOf(ms)] = (byHour[_bucketOf(ms)] ?? 0) + 1;
  }
  if (byHour.isNotEmpty) {
    return (byHour.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first.key;
  }

  final split = mealSplit(s.nutrition.goal);
  for (final m in matches) {
    if (m.slot case final i? when i >= 0 && i < split.length) return split[i.toInt()].$1;
  }
  return null;
}

/// The household measure [grams] of [food] is most plausibly a whole number of, or null.
///
/// One function rather than the test and the answer being computed separately, because they
/// disagreed: 58 g of bread matched "four very thin slices" before it matched "two slices", and
/// the plan was then resized in fifteen-gram steps to 90 g — a weight that is not a whole number
/// of any slice of bread. Best relative fit wins, fewest units breaks the tie, so a recipe
/// written as two slices grows to three rather than to six of something smaller.
double? _unitStep(Food? food, double grams) {
  double? best;
  var bestError = double.infinity;
  var bestUnits = 0;
  for (final portion in food?.portions ?? const <FoodPortion>[]) {
    for (final n in const [1, 2, 3, 4]) {
      final g = portion.g * n;
      if (g <= 0) continue;
      final error = (grams - g).abs() / g;
      if (error > 0.15) continue;
      if (error < bestError - 1e-9 || (error <= bestError + 1e-9 && n < bestUnits)) {
        bestError = error;
        bestUnits = n;
        best = portion.g;
      }
    }
  }
  return best;
}

/// Which role a logged item plays in the meal it was logged as part of.
///
/// A recipe the user wrote down is a list of foods and grams; it does not say which of them is
/// the thing the meal is named after and which is the oil it was cooked in. This reads that off
/// what the app already knows about each food. The order is the decision, not the table: a
/// drink is fixed even if it happens to carry the most protein, and fat is a trace whatever
/// else it is.
PartRole _roleOf(MealItem item, {required double mealKcal, required bool isAnchor}) {
  final food = foods[item.fid];
  if (item.g <= 0) return PartRole.fixed;
  if (food?.cat == 'drink') return PartRole.fixed;
  if (mealKcal > 0 && item.kcal < mealKcal * 0.03) return PartRole.fixed;
  if (food?.cat == 'fat' || item.g <= 20) return PartRole.trace;
  if (food?.cat == 'veg') return PartRole.side;
  if (isAnchor) return PartRole.flex;
  // Bread and tortillas are eaten in slices, and a recipe written as two of them should be
  // resized to three rather than to 2.4. A household measure only counts as the unit when the
  // recipe was actually written in multiples of it.
  if (food?.cat == 'carb' && _unitStep(food, item.g) != null) return PartRole.unit;
  return PartRole.flex;
}

/// A logged or saved meal turned into something the planner can resize.
PlanCandidate candidateOf(List<MealItem> items, {required String name, String? slot}) {
  final mealKcal = items.fold(0.0, (a, i) => a + i.kcal);

  // Whichever item carries the most protein is what the meal is built around.
  var anchor = -1;
  var anchorP = 0.0;
  for (var i = 0; i < items.length; i++) {
    if (items[i].p > anchorP) {
      anchorP = items[i].p;
      anchor = i;
    }
  }

  final parts = <MealPart>[];
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    final role = _roleOf(item, mealKcal: mealKcal, isAnchor: i == anchor);
    final step = role == PartRole.unit ? _unitStep(foods[item.fid], item.g) : null;
    parts.add((base: item.copy(), role: role, step: step));
  }
  return (name: name, slot: slot, parts: parts);
}

/// Everything the user has told the app they eat, most worth proposing first.
///
/// Saved recipes lead, in the order `orderedTemplates` already argues for — frequency ahead of
/// recency, so a weekday breakfast outranks last night's dinner. Meals logged the same way three
/// times follow: they are the same evidence one step before the user has agreed to keep it, and
/// they are capped at one per slot so three near-identical breakfasts cannot crowd out the day.
List<PlanCandidate> userCandidates(AppState s) {
  final out = <PlanCandidate>[];

  for (final tpl in orderedTemplates(s)) {
    final portion = tpl.portion();
    if (portion.isEmpty) continue;
    out.add(candidateOf(
      portion,
      name: tpl.n,
      // What the user filed it under wins outright. They know when they eat it.
      slot: tpl.slot ?? inferSlot(s, signatureOf(portion)),
    ));
  }

  final claimed = <String>{};
  for (final repeat in repeatedMeals(s)) {
    final slot = inferSlot(s, repeat.signature);
    if (slot == null || !claimed.add(slot)) continue;
    out.add(candidateOf(
      repeat.example.items,
      // Unnamed by definition — this is a habit the user has not written down yet. Their own
      // word for the meal is the only part of it the app has to supply, and it is one key.
      name: t('Your usual {0}', t(slot).toLowerCase()),
      slot: slot,
    ));
  }

  return out;
}
