import 'dart:math' as math;

import '../data/models/app_state.dart';
import 'foods.dart';
import 'format.dart';
import 'i18n.dart';
import 'nutrition.dart';

/// The advice layer: explaining the target, teaching density, and deciding what to say next.
///
/// Kept apart from nutrition.dart on purpose — that file is arithmetic and this one is
/// judgement. Everything here is a heuristic somebody chose, and the thresholds below are
/// stated as constants rather than buried in conditions so they can be argued with.
///
/// The rule this whole file obeys: it *offers*. Nothing here changes state. Every function
/// returns something for the UI to present with a way to decline.

/// One line of the "why this number" breakdown.
typedef TargetStep = ({String label, double value, String? note});

/// The arithmetic behind today's calorie target, in the order it happens.
///
/// All of this was already computed and none of it was visible. A number a user cannot take
/// apart is one they can only believe or reject; showing the steps is what lets them adjust it
/// intelligently — and, when it is wrong for them, see *where* it is wrong.
List<TargetStep> targetBreakdown(AppState s, {String? iso}) {
  final b = bmr(s);
  final target = macroTargets(s, iso: iso);
  if (b == null || target == null) return const [];

  final activity = activityFactor(s);
  final withActivity = b * activity;
  final burn = iso == null ? trainingBurn(s) : plannedBurn(s, iso);
  final maintenance = withActivity + burn;
  final g = s.nutrition.goal;
  final rate = goalRate(g);

  return [
    (
      label: t('Resting'),
      value: b,
      note: t('What you burn doing nothing, from your height, weight, age and sex'),
    ),
    (
      label: t('Daily activity'),
      value: withActivity - b,
      note: t('x{0} for everything outside training', fmtNum(activity)),
    ),
    if (burn > 0)
      (
        label: t('Training'),
        value: burn,
        note: iso == null
            ? t('Your average day, from the sessions you have logged')
            : t('This day\'s session, from your plan'),
      ),
    (
      label: t('Maintenance'),
      value: maintenance,
      note: t('Eat this and your weight holds'),
    ),
    if (g.kcal != null)
      (label: t('Your own number'), value: target.kcal, note: t('Set by hand, overriding the rest'))
    else ...[
      if (rate != 0)
        (
          label: rate < 0 ? t('Losing {0} kg a week', fmtNum(rate.abs()))
                          : t('Gaining {0} kg a week', fmtNum(rate.abs())),
          value: rate * kcalPerKg / 7,
          note: t('{0} kcal in a kilo, spread over seven days', fmtNum(kcalPerKg)),
        ),
      if (targetFloored(s, iso: iso))
        (
          label: t('Held at the floor'),
          value: target.kcal - maintenance - rate * kcalPerKg / 7,
          note: t('Going lower would put you under your resting rate'),
        ),
    ],
  ];
}

/// Foods that buy the same calories with more protein.
///
/// Density taught at the moment of choosing is the only time it lands. The comparison is
/// deliberately like-for-like — a swap has to be plausibly the same kind of food, or it is a
/// lecture rather than a suggestion.
List<Food> swapsFor(AppState s, Food food, {int take = 3}) {
  if (food.kcal <= 0) return const [];
  final out = [
    for (final f in foods.all(s))
      if (f.id != food.id &&
          f.cat == food.cat &&
          // Within a third of the calories: close enough to be a real substitution.
          (f.kcal - food.kcal).abs() <= food.kcal * 0.34 &&
          // ...and worth making. A rounding-error improvement is noise.
          f.proteinDensity >= food.proteinDensity * 1.25 &&
          f.p > food.p)
        f
  ]..sort((a, b) => b.proteinDensity.compareTo(a.proteinDensity));
  return out.take(take).toList();
}

/// The one thing worth working on right now.
///
/// Ordered by what actually moves the outcome: you cannot hit a target you are not measuring,
/// protein is what protects lean mass, and total calories decide the direction. Everything
/// else is refinement. Only ever one at a time — a list of five things to fix is a list nobody
/// acts on.
enum NutritionFocus { logConsistently, hitProtein, hitCalories, refine }

/// Days of history to judge against.
const _focusWindow = 14;

/// Below this many logged days in the window, nothing else can be assessed honestly.
const _minLoggedDays = 7;

/// A day counts as hitting protein at this share of target.
const _proteinHit = 0.8;

/// Outside this band around the calorie target, a day counts as a miss.
const _kcalBand = 0.15;

/// What to work on, and the number that says so.
typedef Focus = ({NutritionFocus what, int loggedDays, double proteinRate, double kcalRate});

Focus focusOf(AppState s) {
  final cutoff = DateTime.now().subtract(const Duration(days: _focusWindow));
  final days = <String>{
    for (final m in s.meals)
      if (m.items.isNotEmpty && !dayOf(m.d).isBefore(cutoff)) m.d
  }.toList();

  if (days.length < _minLoggedDays) {
    return (
      what: NutritionFocus.logConsistently,
      loggedDays: days.length,
      proteinRate: 0,
      kcalRate: 0,
    );
  }

  var proteinHits = 0;
  var kcalHits = 0;
  for (final d in days) {
    final target = macroTargets(s, iso: d);
    if (target == null) continue;
    final eaten = dayTotals(s, d);
    if (target.p > 0 && eaten.p >= target.p * _proteinHit) proteinHits++;
    if (target.kcal > 0 &&
        (eaten.kcal - target.kcal).abs() <= target.kcal * _kcalBand) {
      kcalHits++;
    }
  }
  final proteinRate = proteinHits / days.length;
  final kcalRate = kcalHits / days.length;

  final what = proteinRate < _proteinHit
      ? NutritionFocus.hitProtein
      : kcalRate < 0.6
          ? NutritionFocus.hitCalories
          : NutritionFocus.refine;

  return (
    what: what,
    loggedDays: days.length,
    proteinRate: proteinRate,
    kcalRate: kcalRate,
  );
}

/// A change to the target the evidence supports, for the user to accept or decline.
typedef Adjustment = ({double kcal, double delta, String reason, Evolution ev});

/// Only offer once the residual is big enough to be real.
const _minGapKg = 0.5;

/// ...and do not ask again for this long after being turned down.
const _renagDays = 14;

/// A target adjustment the scale is asking for.
///
/// [evolution] already knows the log and the scale disagree. This turns that into a number and
/// hands it to the user — it does not apply it. The gap is converted to a daily calorie
/// correction over the window it was observed across, then applied through the goal's manual
/// override, which already exists and already wins over the computed target.
///
/// Returns null unless the evidence is worth acting on: a reliable window, a gap over
/// [_minGapKg], and either no recent dismissal or a materially changed picture since.
Adjustment? suggestedAdjustment(AppState s) {
  final ev = evolution(s);
  if (ev == null || !ev.reliable) return null;
  if (ev.gap.abs() < _minGapKg) return null;

  final days = math.max(ev.days, 1);
  // A positive gap means the scale came in above the prediction, so the target is too generous
  // and has to come down.
  final delta = -ev.gap * kcalPerKg / days;
  // A correction smaller than this is inside the noise of everything upstream of it.
  if (delta.abs() < 50) return null;

  final current = macroTargets(s);
  if (current == null) return null;

  final dismissed = s.nutrition.dismissedAdj;
  if (dismissed != null) {
    final since = DateTime.now().millisecondsSinceEpoch - dismissed;
    if (since < _renagDays * 86400000) return null;
  }

  return (
    kcal: (current.kcal + delta).roundToDouble(),
    delta: delta,
    reason: ev.gap > 0
        ? t('The scale is {0} kg above what your log predicted.', fmtNum(ev.gap.abs()))
        : t('You are {0} kg below what your log predicted.', fmtNum(ev.gap.abs())),
    ev: ev,
  );
}
