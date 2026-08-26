import 'dart:math' as math;

import '../data/models/app_state.dart';
import 'format.dart';
import 'history.dart';
import 'i18n.dart';
import 'met.dart';

/// Turning a training plan into a calorie and macro target, and reading the food log back.
///
/// Every function here is pure and takes the state it needs, for the reason CONTRIBUTING gives
/// about the progression engine: logic that decides what you should do next earns a test, and a
/// test needs a function it can call without a widget tree.
///
/// One number governs the whole file: energy balance. Eat above what you spend and the surplus
/// is stored, eat below it and the deficit is drawn down. Everything else is estimating the two
/// sides of that, and being honest that both are estimates — see [evolution], which exists to
/// show the user how wrong these numbers are for them specifically.

/// Energy in a kilogram of body mass, near enough. The classic 3,500 kcal per pound.
///
/// It describes fat; real weight change is fat plus lean tissue plus a lot of water, which is
/// why a week of scale readings can move the wrong way on a genuine deficit and why [evolution]
/// compares a trend rather than two points.
const kcalPerKg = 7700.0;

/// A set and everything around it — the work, the rest after it, the walk to the next machine.
///
/// Only used for history imported from another app, which carries no clock at all
/// (`start == end == 0`; it is the reason `durPart` suppresses sub-minute durations). A session
/// logged in this app has a real wall time and never falls back to this.
const _minutesPerSet = 3.0;

/// Assumed working time in a planned set, before the rest interval the profile already sets.
const _workSeconds = 45.0;

/// Non-exercise activity only.
///
/// The familiar 1.2-1.9 multipliers already fold training in, which is exactly what must not
/// happen here: this app knows what was actually trained and adds it from the log. Using the
/// usual numbers on top of a measured session burn counts the gym twice, which is the single
/// most common way a calorie target comes out several hundred kcal too high.
const _activity = <String, double>{
  'sedentary': 1.2, // desk work, little walking
  'light': 1.3,
  'moderate': 1.4,
  'active': 1.5, // on your feet most of the day
};

/// kg, whatever the profile displays.
///
/// `AppState.unit` is a label and never converts what is stored, so an `lb` profile holds
/// pounds in every `w` and `bw` in the state. Every formula below is metric, so this is the
/// one door they all come through.
double kgOf(double w, String unit) => unit == 'lb' ? w * 0.45359237 : w;

/// The most recent weigh-in, in kg. Null when the user has never weighed in.
double? bodyKg(AppState s) {
  final bw = lastBW(s);
  if (bw == null || bw.w <= 0) return null;
  return kgOf(bw.w, s.unit);
}

/// Resting metabolic rate, Mifflin-St Jeor.
///
/// Chosen over Harris-Benedict because it was fitted on a modern population and is the equation
/// the ADA recommends; the two differ by ~5% and neither is better than ±10% for an individual.
/// Returns null rather than guessing when the profile is incomplete — a target built on an
/// assumed age is worse than no target, because it looks just as authoritative.
double? bmrOf(BodyProfile p, double kg) {
  if (!p.isComplete || kg <= 0) return null;
  final base = 10 * kg + 6.25 * p.height! - 5 * p.age!;
  return base + (p.sex == 'female' ? -161 : 5);
}

double? bmr(AppState s) {
  final kg = bodyKg(s);
  return kg == null ? null : bmrOf(s.nutrition.profile, kg);
}

double activityFactor(AppState s) =>
    _activity[s.nutrition.profile.activity] ?? _activity['light']!;

/// Wall-clock length of a finished session, in minutes.
double sessionMinutes(Workout w) {
  final ms = w.end - w.start;
  if (ms > 0) return ms / 60000;
  return setsDone(w) * _minutesPerSet;
}

/// Calories a finished session cost, over and above simply existing for that long.
///
/// The `- 1` matters. A MET already includes resting metabolism, and [tdee] counts every hour
/// of the day at rest through the BMR term. Charging the full MET here would bill the resting
/// hour twice and inflate a one-hour session by roughly 80 kcal.
///
/// Cardio and strength are apportioned rather than averaged: cardio sets record their own
/// minutes, so their cost is computed directly and the wall clock left over is what the
/// strength work took. A session that is entirely one or the other collapses to the obvious
/// answer either way.
double workoutBurn(Workout w, double kg) {
  if (kg <= 0) return 0;

  var kcal = 0.0;
  var cardioMin = 0.0;
  var strengthNum = 0.0;
  var strengthDen = 0.0;

  for (final e in w.entries) {
    final met = metOfEntry(e);
    if (modeOf(e.cfg) == 'cardio') {
      for (final s in e.sets) {
        final min = s.done ? (s.min ?? 0) : 0;
        if (min <= 0) continue;
        cardioMin += min;
        kcal += (met - 1) * kg * (min / 60);
      }
    } else {
      final sets = e.sets.where((s) => s.done).length;
      if (sets == 0) continue;
      strengthNum += met * sets;
      strengthDen += sets;
    }
  }

  final rest = math.max(0.0, sessionMinutes(w) - cardioMin);
  if (rest > 0 && strengthDen > 0) {
    kcal += (strengthNum / strengthDen - 1) * kg * (rest / 60);
  }
  return kcal;
}

/// How long a routine would take if it were done as written.
double plannedMinutes(AppState s, Routine? r) {
  var min = 0.0;
  for (final cfg in r?.ex ?? const <ExerciseConfig>[]) {
    final sets = math.max(1, (cfg.sets ?? 1).round());
    min += switch (modeOf(cfg)) {
      'cardio' => sets * (cfg.min ?? 0),
      'time' => sets * ((cfg.sec ?? _workSeconds) + s.restSec) / 60,
      _ => sets * (_workSeconds + s.restSec) / 60,
    };
  }
  return min;
}

/// What a routine would cost, before it has been done.
///
/// This is what lets a target exist on the morning of a training day rather than only after it.
double burnOfRoutine(AppState s, Routine? r) {
  final kg = bodyKg(s);
  if (r == null || kg == null) return 0;
  return (metOfRoutine(r) - 1) * kg * (plannedMinutes(s, r) / 60);
}

/// The planned cost of one calendar day, honouring per-date overrides.
double plannedBurn(AppState s, String iso) =>
    burnOfRoutine(s, effectiveRoutine(s, iso));

/// The planned cost of a full week of the weekly plan.
double plannedWeeklyBurn(AppState s) {
  var total = 0.0;
  for (final id in s.week.values) {
    for (final r in s.routines) {
      if (r.id == id) total += burnOfRoutine(s, r);
    }
  }
  return total;
}

/// Average daily training burn, in kcal.
///
/// Prefers what was actually logged over the last [days]; falls back to the plan when there is
/// no history yet, so a target exists from the moment a plan is set rather than a week later.
double trainingBurn(AppState s, {int days = 7}) {
  final kg = bodyKg(s);
  if (kg == null) return 0;
  final cutoff = DateTime.now().subtract(Duration(days: days));
  var total = 0.0;
  var n = 0;
  for (final w in s.workouts) {
    if (dayOf(w.d).isBefore(cutoff)) continue;
    total += workoutBurn(w, kg);
    n++;
  }
  if (n == 0) return plannedWeeklyBurn(s) / 7;
  return total / days;
}

/// Total daily energy expenditure.
///
/// With no [iso] this is the weekly picture: resting metabolism, scaled for non-exercise
/// activity, plus the average day's training. Averaged rather than same-day because the plan is
/// weekly and eating 700 kcal more on Tuesdays is not a thing anyone sustains — the food you
/// eat on a rest day still fuels the session either side of it.
///
/// Pass [iso] for the per-day view the week strip draws, which uses that specific day's planned
/// session instead of the average.
double? tdee(AppState s, {String? iso}) {
  final b = bmr(s);
  if (b == null) return null;
  final burn = iso == null ? trainingBurn(s) : plannedBurn(s, iso);
  return b * activityFactor(s) + burn;
}

/// 'cut' | 'maintain' | 'gain'. Null means never chosen — see [NutritionGoal.mode].
String goalMode(NutritionGoal g) => g.mode ?? 'maintain';

/// Meals per day the plan splits into.
int mealsPerDay(NutritionGoal g) => (g.meals ?? 4).round().clamp(1, 8);

/// Intended kg per week, signed.
///
/// The defaults are deliberately unambitious: about 0.5 kg a week down is the fastest most
/// people hold on to muscle through, and 0.25 kg a week up is roughly the ceiling above which
/// the gain stops being lean.
double goalRate(NutritionGoal g) =>
    g.rate ??
    switch (goalMode(g)) {
      'cut' => -0.5,
      'gain' => 0.25,
      _ => 0.0,
    };

/// Grams of protein per kg of body weight.
///
/// Highest on a cut, which reads backwards until you remember what a cut is for: in a deficit
/// the body is willing to spend lean tissue, and protein plus resistance training is what stops
/// it. This is a lifting app, so that is the whole point of the feature.
double proteinPerKg(NutritionGoal g) => goalMode(g) == 'cut' ? 2.0 : 1.8;

/// A calorie and macro target, in kcal and grams.
typedef Macros = ({double kcal, double p, double c, double f});

/// The target for a day. Null when the profile is too incomplete to estimate anything.
Macros? macroTargets(AppState s, {String? iso}) {
  // Routed through the same helper targetFloored reads, so the two can never disagree about
  // what the goal asked for — and computed once, because tdee() reads DateTime.now() for its
  // trailing window and two calls either side of a day boundary would not have to agree.
  var kcal = _uncappedTarget(s, iso: iso);
  final b = bmr(s);
  final kg = bodyKg(s);
  if (kcal == null || b == null || kg == null) return null;

  final g = s.nutrition.goal;
  // No goal may prescribe eating below resting metabolism. A deficit that steep stops being a
  // diet and starts being a reason to lose muscle and a period.
  kcal = math.max(kcal, b * 1.1);

  var p = g.protein ?? proteinPerKg(g) * kg;
  // Fat has a floor as well as a share: it is where the fat-soluble vitamins and the sex
  // hormones come from, and 25% of a deep deficit can land under what that needs.
  var f = math.max((g.fatPct ?? 25) / 100 * kcal / 9, 0.6 * kg);

  final floor = p * 4 + f * 9;
  if (floor > kcal) {
    // A steep deficit at high body weight can price protein and fat alone above the target.
    // Scale both back together rather than showing a plan whose own numbers do not add up.
    final k = kcal / floor;
    p *= k;
    f *= k;
  }
  final c = math.max(0.0, (kcal - p * 4 - f * 9) / 4);
  return (kcal: kcal, p: p, c: c, f: f);
}

/// The target the goal asked for, before the resting-metabolism floor is applied.
double? _uncappedTarget(AppState s, {String? iso}) {
  final t = tdee(s, iso: iso);
  if (t == null) return null;
  final g = s.nutrition.goal;
  return g.kcal ?? t + goalRate(g) * kcalPerKg / 7;
}

/// Whether the goal's rate had to be held back to keep the target above resting metabolism.
///
/// Worth surfacing rather than hiding: a sedentary profile asking for 0.5 kg a week will often
/// hit this, and the honest answer is not to quietly serve a smaller deficit but to say that
/// the rate needs either more activity or more patience. Without this the user sees a target
/// that does not match the goal they set and has no way to find out why.
bool targetFloored(AppState s, {String? iso}) {
  final want = _uncappedTarget(s, iso: iso);
  final b = bmr(s);
  if (want == null || b == null) return false;
  return want < b * 1.1;
}

/// The weekly rate the floored target actually delivers, in kg. Signed, like [goalRate].
double? achievableRate(AppState s, {String? iso}) {
  final t = tdee(s, iso: iso);
  final target = macroTargets(s, iso: iso);
  if (t == null || target == null) return null;
  return (target.kcal - t) * 7 / kcalPerKg;
}

/// Meals logged on one day, in the order they were logged.
List<Meal> mealsOn(AppState s, String iso) =>
    [for (final m in s.meals) if (m.d == iso) m];

Macros _sum(Iterable<Meal> meals) {
  var kcal = 0.0, p = 0.0, c = 0.0, f = 0.0;
  for (final m in meals) {
    for (final i in m.items) {
      kcal += i.kcal;
      p += i.p;
      c += i.c;
      f += i.f;
    }
  }
  return (kcal: kcal, p: p, c: c, f: f);
}

/// What was eaten on one day.
Macros dayTotals(AppState s, String iso) => _sum(mealsOn(s, iso));

/// What was eaten in the calendar week containing [iso].
///
/// Buckets with [weekKey], the same function the stats screen and the streak counter use — its
/// behaviour is pinned against the original JavaScript by a three-year fixture, and a second
/// week-bucketing rule that disagreed with it by a day would be a genuinely nasty bug.
Macros weekTotals(AppState s, String iso) {
  final key = weekKey(iso);
  return _sum([for (final m in s.meals) if (weekKey(m.d) == key) m]);
}

/// The days a week's plan trains on, as ISO dates, Monday first.
List<String> weekDays(String iso) {
  final monday = DateTime.fromMillisecondsSinceEpoch(mondayOf(iso));
  return [
    for (var i = 0; i < 7; i++)
      isoOf(DateTime(monday.year, monday.month, monday.day + i, 12))
  ];
}

/// Totals for a day, split into what each meal slot holds.
///
/// Slot names are English source strings, which is how every string in this app is keyed.
const _splits = <int, List<(String, double)>>{
  1: [('All day', 1.0)],
  2: [('Lunch', .55), ('Dinner', .45)],
  3: [('Breakfast', .3), ('Lunch', .4), ('Dinner', .3)],
  4: [('Breakfast', .25), ('Lunch', .35), ('Snack', .1), ('Dinner', .3)],
  5: [('Breakfast', .22), ('Snack', .1), ('Lunch', .3), ('Snack', .08), ('Dinner', .3)],
  6: [
    ('Breakfast', .2),
    ('Snack', .1),
    ('Lunch', .27),
    ('Snack', .08),
    ('Dinner', .25),
    ('Snack', .1),
  ],
};

/// How a day's calories divide across its meals.
///
/// The splits are conventional rather than optimal — total intake and total protein are what
/// move body composition, and meal timing is a rounding error next to them. They exist so the
/// day arrives pre-portioned instead of asking the user to do the arithmetic.
List<(String, double)> mealSplit(NutritionGoal g) {
  final n = mealsPerDay(g);
  final split = _splits[n];
  if (split != null) return split;
  // A count the table has no shape for — only reachable from a hand-edited or imported state,
  // since the control offers 2 to 6. Numbered and split evenly. The name is resolved here
  // rather than left as a template: callers pass these through `t()` and a placeholder nobody
  // substitutes would reach the screen as the literal "Meal {0}".
  return [for (var i = 0; i < n; i++) (t('Meal {0}', i + 1), 1 / n)];
}

/// A week's calorie budget, and what is left of it.
typedef WeekBudget = ({
  double budget,
  double spent,
  double left,
  int daysLeft,
  double perDayLeft,
});

/// The week containing [iso], priced day by day.
///
/// Energy balance is weekly, not daily, and a daily-only frame turns one heavy Saturday into a
/// failure rather than into something Tuesday already paid for. The budget is summed from each
/// day's own target, so a week with three training days in it is worth more than a week with
/// one — the link back to the plan is preserved rather than averaged away.
///
/// [daysLeft] counts today as still spendable: at breakfast on Wednesday there are five days
/// left in the week, not four.
WeekBudget weekBudget(AppState s, String iso) {
  final days = weekDays(iso);
  final today = todayISO();

  var budget = 0.0;
  var spent = 0.0;
  var daysLeft = 0;

  for (final d in days) {
    budget += macroTargets(s, iso: d)?.kcal ?? 0;
    // A future day has not been eaten yet even if something is logged against it, and a past
    // day is settled whether or not anything was.
    if (d.compareTo(today) <= 0) {
      spent += dayTotals(s, d).kcal;
    }
    if (d.compareTo(today) >= 0) daysLeft++;
  }

  final left = budget - spent;
  return (
    budget: budget,
    spent: spent,
    left: left,
    daysLeft: daysLeft,
    // What is left, spread over what remains — the number that actually guides a decision.
    // Past the end of the week there is nothing left to spread it over.
    perDayLeft: daysLeft > 0 ? left / daysLeft : 0,
  );
}

/// A stable key for "the same meal, logged again".
///
/// Built from what was eaten and how much of it, so a breakfast repeated on Tuesday matches
/// Monday's. Names are ignored where a food id exists — the same food typed by hand and picked
/// from the catalogue are the same breakfast. Grams are rounded to five so a 148 g and a 150 g
/// chicken breast do not read as two different meals; nobody weighs that precisely and the
/// difference is well inside the error the rest of this file already carries.
String signatureOf(Iterable<MealItem> items) {
  final parts = [
    for (final i in items)
      '${i.fid ?? i.n ?? ''}:${(i.g / 5).round() * 5}'
  ]..sort();
  return parts.join('|');
}

/// Meals logged the same way at least [min] times that are not saved yet.
///
/// The evidence behind offering to save one. Nothing is saved automatically: a suggestion the
/// user accepts is a meal they will use, and one the app invents is clutter they have to delete.
List<({String signature, Meal example, int count})> repeatedMeals(AppState s, {int min = 3}) {
  final saved = {for (final x in s.nutrition.templates) signatureOf(x.items)};
  final counts = <String, int>{};
  final example = <String, Meal>{};
  for (final m in s.meals) {
    if (m.items.isEmpty) continue;
    final sig = signatureOf(m.items);
    if (saved.contains(sig)) continue;
    counts[sig] = (counts[sig] ?? 0) + 1;
    example[sig] ??= m;
  }
  final out = [
    for (final e in counts.entries)
      if (e.value >= min) (signature: e.key, example: example[e.key]!, count: e.value)
  ]..sort((a, b) => b.count.compareTo(a.count));
  return out;
}

/// Saved meals, most useful first: what gets logged often and recently.
///
/// Frequency ahead of recency, because a breakfast eaten every weekday should outrank the
/// dinner you happened to have last night.
List<MealTemplate> orderedTemplates(AppState s) {
  final out = [...s.nutrition.templates];
  out.sort((a, b) {
    final byUse = (b.used ?? 0).compareTo(a.used ?? 0);
    return byUse != 0 ? byUse : (b.last ?? 0).compareTo(a.last ?? 0);
  });
  return out;
}

/// Days that have food logged against them, most recent first.
List<String> loggedDays(AppState s, {int take = 14, String? excluding}) {
  final days = <String>{
    for (final m in s.meals)
      if (m.items.isNotEmpty && m.d != excluding) m.d
  }.toList()
    ..sort((a, b) => b.compareTo(a));
  return days.take(take).toList();
}

/// What the log predicted against what the scale did.
///
/// [predicted] is the weight change the logged energy balance implies; [observed] is what the
/// body-weight series actually recorded over the same window; [gap] is observed minus predicted,
/// in kg.
///
/// Reporting the gap is the point of the whole feature, and it is the part every calorie app
/// gets wrong. All the arithmetic upstream of here — a BMR equation fitted to a population, MET
/// values inferred from a body part, a portion size someone eyeballed — carries error, and
/// presenting the result as a measurement makes it a number to be believed rather than used.
/// The gap turns three fallible estimates into one honest question: over this month, was the
/// plan right about you?
///
/// A consistently negative gap means the numbers here are optimistic — under-logged food or an
/// over-generous burn — and the target should come down regardless of what the equations say.
typedef Evolution = ({
  double predicted,
  double observed,
  double gap,
  double dailyBalance,
  int days,
  int loggedDays,
  bool reliable,
});

/// Compares predicted with observed weight change over the last [days].
///
/// Returns null when there is nothing to compare: no target, or fewer than two weigh-ins.
Evolution? evolution(AppState s, {int days = 90}) {
  final start = DateTime.now().subtract(Duration(days: days));
  final weighIns = [for (final b in s.bodyweight) if (!dayOf(b.d).isBefore(start)) b];
  if (weighIns.length < 2) return null;

  // Days with any food logged at all. A day with nothing on it is a day nobody logged, not a
  // day of fasting, so it must not be counted as a deficit.
  final logged = <String>{for (final m in s.meals) if (!dayOf(m.d).isBefore(start)) m.d};
  if (logged.isEmpty) return null;

  // Every past day is costed at today's body weight, not the weight it was lived at. Doing it
  // properly would mean interpolating the weigh-in series for each day; the error that avoids
  // is about 30 kcal a day across a 3 kg change, which is small next to the portion sizes and
  // the MET table feeding into the same sum. It does mean two profiles with identical logs and
  // different current weights get slightly different predictions, which is correct — the
  // heavier one really did spend more.
  var balance = 0.0;
  for (final iso in logged) {
    final target = macroTargets(s, iso: iso);
    final t = tdee(s, iso: iso);
    if (target == null || t == null) continue;
    balance += dayTotals(s, iso).kcal - t;
  }

  final first = kgOf(weighIns.first.w, s.unit);
  final last = kgOf(weighIns.last.w, s.unit);
  final span = dayOf(weighIns.last.d).difference(dayOf(weighIns.first.d)).inDays;

  final predicted = balance / kcalPerKg;
  final observed = last - first;

  return (
    predicted: predicted,
    observed: observed,
    gap: observed - predicted,
    dailyBalance: balance / logged.length,
    days: span,
    loggedDays: logged.length,
    // Under a fortnight of logs, or a fortnight of scale readings, the noise is bigger than the
    // signal: day-to-day water movement alone is worth a kilo either way.
    reliable: logged.length >= 14 && span >= 14,
  );
}
