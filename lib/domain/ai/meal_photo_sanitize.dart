import '../foods.dart';
import 'meal_photo_draft.dart';

/// Turns what a model said into something the app is willing to show, and eventually to log.
///
/// Pure: no Flutter, no I/O, no globals. The catalogue lookup arrives as a function rather than
/// through `foods[id]` because `Foods` loads from `rootBundle`, and reaching for it here would
/// drag a Flutter test binding into every bounds check in this file.
///
/// The rule this whole file exists to enforce: **a model's numbers never reach the log for a food
/// the catalogue carries.** It may say *what* is on the plate and *how much*; the macros come
/// from USDA either way. Everything else here is guarding the remaining case — a food the
/// catalogue does not have — where there is no second source and the numbers have to be checked
/// against themselves instead.
///
/// And a second rule, learned the hard way: **a catalogue id the model would not call the same
/// food is not a match.** An unrecognised dish once came back logged as a food the user had
/// registered by hand, because the prompt asked for the nearest catalogue entry and this file had
/// no way to tell a match from a near-neighbour. The prompt now asks the model to say which it
/// meant, and [_saysNotSame] is where that answer is acted on rather than trusted to prose.

typedef FoodLookup = Food? Function(String id);

/// The most items one photograph can produce.
///
/// A plate has a handful of things on it. A model that returns thirty has started naming garnish,
/// and the review sheet stops being reviewable long before that.
const _maxItems = 12;

/// Plausible portion bounds, in grams.
///
/// Tighter than the 5,000 g `foodDetailSheet` allows for a portion typed by hand, and on purpose:
/// a number somebody typed is a claim, and this one is a guess.
const _minGrams = 1.0;
const _maxGrams = 2000.0;

/// Per-100 g bounds for a free-form food — the exact limits `customFoodSheet` puts on a food the
/// user types in themselves. 100 g of anything cannot hold more than 100 g of one macro, and pure
/// fat is about 900 kcal. Reusing the numbers is the point: a food the model invented is held to
/// the same standard as one a person did.
const _maxPer100Kcal = 900.0;
const _maxPer100Macro = 100.0;

/// How far energy may drift from the macros before the macros win.
///
/// Atwater — 4 kcal a gram of protein and carbohydrate, 9 a gram of fat — is arithmetic, and three
/// macro estimates are less likely to be jointly wrong than one energy figure is. The absolute
/// floor keeps a 40 kcal vegetable from being "corrected" over a rounding difference.
const _atwaterTolerance = 0.25;
const _atwaterFloor = 30.0;

/// How much wider than the estimate a range may be before it stops being information.
const _maxRangeFactor = 3.0;

MealDraft sanitizeMealGuess(Object? raw, {required FoodLookup lookup}) {
  // 1. Envelope. Anything that is not the agreed shape is a failure to read, not a crash — this
  //    function is called on whatever a third party returned and must never throw.
  if (raw is! Map) return MealDraft.empty(DraftProblem.unreadable);
  final map = Map<String, dynamic>.from(raw);

  final problems = <DraftProblem>{};

  // 2. The model saying "that is not a meal" is a specific answer, not an error. The sheet says
  //    something different for it, so it must stay distinguishable from an empty result.
  if (map['notFood'] == true) return MealDraft.empty(DraftProblem.notFood);

  final rawItems = map['items'];
  if (rawItems is! List || rawItems.isEmpty) {
    return MealDraft.empty(DraftProblem.noItems);
  }

  var entries = [
    for (final e in rawItems)
      if (e is Map) Map<String, dynamic>.from(e)
  ];

  // 3. Cap, keeping the largest by declared weight. The cap should drop the parsley, not the
  //    steak, so it cannot simply take the first twelve.
  if (entries.length > _maxItems) {
    problems.add(DraftProblem.tooManyItems);
    entries = [...entries]
      ..sort((a, b) => (_num(b['grams']) ?? 0).compareTo(_num(a['grams']) ?? 0));
    entries = entries.take(_maxItems).toList();
  }

  final items = <DraftItem>[];
  for (final e in entries) {
    final item = _item(e, lookup, problems);
    if (item != null) items.add(item);
  }

  // 10. Two rows resolving to the same catalogue food are one food. Two eggs frequently come back
  //     as two entries, and `addMealItem` would otherwise write two lines for one thing.
  final merged = _merge(items);

  if (merged.isEmpty) problems.add(DraftProblem.noItems);

  return MealDraft(
    items: merged,
    confidence: _confidence(map['confidence']),
    problems: problems.toList(),
  );
}

DraftItem? _item(Map<String, dynamic> e, FoodLookup lookup, Set<DraftProblem> problems) {
  final name = (e['name'] is String ? e['name'] as String : '').trim();

  // 4. Resolve the id. A miss becomes free-form rather than the catalogue's "Unknown food"
  //    placeholder — `foods.or(id)` returns a food whose macros are all zero, and logging that
  //    would put a silent 0 kcal row in the day. This is the most load-bearing line in the file.
  final fid = e['fid'] is String ? (e['fid'] as String).trim() : '';
  var food = fid.isEmpty ? null : lookup(fid);
  if (fid.isNotEmpty && food == null) problems.add(DraftProblem.unknownFid);

  // 4b. The model's own verdict on its id. Parsed only when it could change something: when the
  //     id already resolved and was called the same food, the model was told not to send macros
  //     at all, and reading them here would let a stray `per100` raise problems for numbers this
  //     item is never going to use.
  final demote = food != null && _saysNotSame(e['match']);
  final own = (food == null || demote) ? _per100(e['per100'], problems) : null;

  if (demote) {
    if (own != null) {
      // The id goes, and with it the catalogue's macros and its name. What is left is what the
      // model actually saw: a food this app does not have yet, which the review sheet offers to
      // save. This is the line that stops an arepa being logged as a tortilla.
      food = null;
    } else {
      // Nothing to fall back to. Dropping the item would under-count a day the user really ate,
      // so the id stays and the sheet says out loud that it needs a look.
      problems.add(DraftProblem.unsureMatch);
    }
  }

  if (food == null && name.isEmpty) return null;

  // 5. Grams. A portion that is not a usable number at all takes the item with it: there is
  //    nothing to show and nothing to correct.
  final rawGrams = _num(e['grams']);
  if (rawGrams == null || !rawGrams.isFinite || rawGrams <= 0) return null;
  var grams = rawGrams;
  if (grams < _minGrams || grams > _maxGrams) {
    problems.add(DraftProblem.gramsClamped);
    grams = grams.clamp(_minGrams, _maxGrams);
  }

  // 6. The range. Missing bounds collapse to the estimate; a swapped pair is sorted rather than
  //    rejected, because a model that put low and high the wrong way round still gave three
  //    useful numbers. Then the span is capped: a range three times wider than the estimate is
  //    not information, and it makes the review chips useless.
  final bounds = [
    _finite(_num(e['gramsLow'])) ?? grams,
    grams,
    _finite(_num(e['gramsHigh'])) ?? grams,
  ]..sort();
  final low = bounds.first.clamp(grams / _maxRangeFactor, grams);
  final high = bounds.last.clamp(grams, grams * _maxRangeFactor);

  Per100? per100;
  if (food == null) {
    per100 = own;
    // 9. A free-form food with nothing behind it contributes zero and would silently under-count
    //    the day — the exact failure the log's own reasoning warns about, where an unlogged day
    //    reads as a day nobody ate. Drop it and let the sheet offer to add it by hand.
    if (per100 == null) {
      problems.add(DraftProblem.noMacros);
      return null;
    }
  }

  return DraftItem(
    name: name.isEmpty ? (food?.n ?? '') : name,
    grams: grams,
    gramsLow: low,
    gramsHigh: high,
    food: food,
    per100: per100,
    cat: _cat(e['cat']),
    note: e['note'] is String ? e['note'] as String : null,
  );
}

/// Whether the model disowned its own id.
///
/// Absent reads as "same", deliberately: a provider that drops the field — an older adapter, a
/// model answering without constrained decoding — must not have every catalogue match in the
/// answer quietly demoted to a free-form guess. Anything the model *does* say that is not 'same'
/// is taken at its word.
bool _saysNotSame(Object? raw) => raw is String && raw != 'same';

/// The category to prefill a saved food with. Never load-bearing, so anything unrecognised falls
/// back rather than failing.
String _cat(Object? raw) =>
    raw is String && foodCategories.contains(raw) ? raw : 'other';

/// Per-100 g macros for a free-form food, clamped and cross-checked, or null when there is
/// nothing usable.
Per100? _per100(Object? raw, Set<DraftProblem> problems) {
  if (raw is! Map) return null;
  final m = Map<String, dynamic>.from(raw);

  // 7. Clamp first, so the Atwater check below runs on numbers that are at least possible.
  final p = (_finite(_num(m['p'])) ?? 0).clamp(0.0, _maxPer100Macro);
  final c = (_finite(_num(m['c'])) ?? 0).clamp(0.0, _maxPer100Macro);
  final f = (_finite(_num(m['f'])) ?? 0).clamp(0.0, _maxPer100Macro);
  var kcal = (_finite(_num(m['kcal'])) ?? 0).clamp(0.0, _maxPer100Kcal);

  // 8. Atwater. Energy that disagrees with the macros loses to them.
  final implied = 4 * p + 4 * c + 9 * f;
  if (kcal <= 0) {
    kcal = implied.clamp(0.0, _maxPer100Kcal);
  } else if (implied > 0) {
    final drift = (kcal - implied).abs();
    if (drift > _atwaterFloor && drift / kcal > _atwaterTolerance) {
      problems.add(DraftProblem.kcalRecomputed);
      kcal = implied.clamp(0.0, _maxPer100Kcal);
    }
  }

  if (kcal <= 0 && p <= 0 && c <= 0 && f <= 0) return null;
  return (kcal: kcal, p: p, c: c, f: f);
}

/// Sums same-food rows, keeping the first row's identity and widening its range with it.
List<DraftItem> _merge(List<DraftItem> items) {
  final out = <DraftItem>[];
  final byFid = <String, int>{};
  for (final i in items) {
    final id = i.food?.id;
    final at = id == null ? null : byFid[id];
    if (at == null) {
      if (id != null) byFid[id] = out.length;
      out.add(i);
      continue;
    }
    final prev = out[at];
    out[at] = DraftItem(
      name: prev.name,
      grams: prev.grams + i.grams,
      gramsLow: prev.gramsLow + i.gramsLow,
      gramsHigh: prev.gramsHigh + i.gramsHigh,
      food: prev.food,
      per100: prev.per100,
      cat: prev.cat,
      note: prev.note,
    );
  }
  return out;
}

DraftConfidence _confidence(Object? raw) => switch (raw) {
      'high' => DraftConfidence.high,
      'medium' => DraftConfidence.medium,
      // Anything unrecognised reads as low. Erring towards "unsure" is the right direction for a
      // number the user is about to trust.
      _ => DraftConfidence.low,
    };

double? _num(Object? v) => switch (v) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };

double? _finite(double? v) => (v == null || !v.isFinite) ? null : v;
