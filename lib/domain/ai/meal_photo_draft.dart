import '../../data/models/app_state.dart';
import '../foods.dart';

/// What a photograph became, before the user has agreed to any of it.
///
/// A draft is not a meal and must never be written like one. Everything here is editable, every
/// number carries a reason, and the only way any of it reaches `AppState` is the user tapping
/// Confirm in the review sheet — which then goes through the ordinary `addMealItem`, exactly as
/// a hand-logged food does.

/// Macros per 100 g, for a food the catalogue does not carry.
typedef Per100 = ({double kcal, double p, double c, double f});

/// Why a draft is not simply what the model said.
///
/// A list rather than a boolean because the review sheet earns its trust by being specific:
/// "2 items couldn't be identified, 1 portion looked implausible and was capped" tells the user
/// where to look, and "something went wrong" tells them to stop using the feature.
enum DraftProblem {
  /// The answer was not the agreed shape at all.
  unreadable,

  /// The model said this is not food.
  notFood,

  /// Nothing survived — either the model returned nothing, or every item was dropped.
  noItems,

  /// More items than the cap; the smallest were dropped.
  tooManyItems,

  /// A food id the catalogue does not carry.
  unknownFid,

  /// A portion outside the plausible range, clamped to it.
  gramsClamped,

  /// Energy disagreed with the macros, so the macros won.
  kcalRecomputed,

  /// A free-form item with no usable macros at all; dropped rather than logged as zero.
  noMacros,
}

/// One food in a draft.
class DraftItem {
  DraftItem({
    required this.name,
    required this.grams,
    required this.gramsLow,
    required this.gramsHigh,
    this.food,
    this.per100,
    this.note,
  });

  /// The catalogue food this resolved to, or null for a free-form item.
  ///
  /// When this is set it is the *only* source of macros. The model's own numbers are discarded,
  /// which is the entire reason the app asks for an id instead of a calorie count: the figures in
  /// the log then come from the same USDA records every hand-logged food comes from, and can be
  /// checked against `Food.src`.
  final Food? food;

  /// What the model called it. Kept even for a catalogue hit, because it is the tell when the id
  /// is plausible but wrong — "Salmon" arriving against a sardine record is only visible if both
  /// the name and the id are present.
  final String name;

  /// The portion, in grams. Mutable: correcting this is the main thing the review sheet is for.
  double grams;

  /// The plausible range the estimate came with. Not a confidence interval — a spread wide enough
  /// to be honest and narrow enough to be useful.
  ///
  /// Final while [grams] is not, deliberately: once the user has typed a number, the range is
  /// still what the model said, and quietly re-centring it around their correction would be the
  /// app inventing a claim nobody made.
  final double gramsLow;
  final double gramsHigh;

  /// Macros per 100 g. Set only when [food] is null — there is no other source then.
  final Per100? per100;

  /// Anything the model wanted to say about this item, e.g. what it used for scale.
  final String? note;

  /// True when this came back as a food the catalogue does not carry.
  bool get isFreeForm => food == null;

  /// This item as something the log can hold.
  ///
  /// The only place a [MealItem] is built out of a draft, so the "catalogue hits use
  /// `Food.portion`" rule has exactly one place it could ever be broken.
  MealItem toMealItem() {
    final f = food;
    if (f != null) return f.portion(grams);
    final p = per100 ?? (kcal: 0.0, p: 0.0, c: 0.0, f: 0.0);
    return MealItem(
      // fid stays null and the name is carried, the same shape a quick-add produces. A free-form
      // item is not pretending to be a catalogue food.
      n: name,
      g: grams,
      kcal: p.kcal * grams / 100,
      p: p.p * grams / 100,
      c: p.c * grams / 100,
      f: p.f * grams / 100,
    );
  }

  DraftItem copyWith({double? grams, Food? food, String? name, Per100? per100}) => DraftItem(
        name: name ?? this.name,
        grams: grams ?? this.grams,
        gramsLow: gramsLow,
        gramsHigh: gramsHigh,
        food: food ?? this.food,
        per100: per100 ?? this.per100,
        note: note,
      );
}

/// How sure the model said it was, overall.
enum DraftConfidence { high, medium, low }

/// A photograph, read.
class MealDraft {
  const MealDraft({
    required this.items,
    this.confidence = DraftConfidence.low,
    this.problems = const [],
  });

  /// A draft that produced nothing, and the one reason why.
  ///
  /// Not const: the reason has to survive into [problems], and that is the whole value of this
  /// constructor — the sheet says something different for "that is not a meal" than it does for
  /// "the answer could not be read".
  MealDraft.empty(DraftProblem problem)
      : items = const [],
        confidence = DraftConfidence.low,
        problems = [problem];

  final List<DraftItem> items;
  final DraftConfidence confidence;
  final List<DraftProblem> problems;

  bool get isEmpty => items.isEmpty;

  bool has(DraftProblem p) => problems.contains(p);

  double get kcal => items.fold(0, (a, i) => a + i.toMealItem().kcal);

  /// The day's total if every portion turned out to be at the bottom of its range, and the top.
  ///
  /// This is the number the sheet shows as a band. It is the honest headline for the whole
  /// feature: a single figure would imply a measurement, and a photograph is not one.
  double get kcalLow => _scaled((i) => i.gramsLow);
  double get kcalHigh => _scaled((i) => i.gramsHigh);

  double _scaled(double Function(DraftItem) grams) {
    var total = 0.0;
    for (final i in items) {
      final g = grams(i);
      total += i.grams <= 0 ? 0 : i.toMealItem().kcal * g / i.grams;
    }
    return total;
  }
}
