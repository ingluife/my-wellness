import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/models/app_state.dart';
import '../../domain/format.dart';
import '../../domain/glyphs.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../domain/nutrition.dart';
import '../../state/app_state_provider.dart';
import '../sheets/plan_sheets.dart';
import '../sheets/weight_sheets.dart';
import '../sheets/calendar_sheet.dart';
import '../sheets/workout_flow.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/pressable.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/line_chart.dart';
import '../widgets/macro_bar.dart';
import '../widgets/media.dart';
import '../widgets/page.dart';

/// Home = what to do now, plus a quick glance. The deep charts and the full history live in
/// Stats; this screen answers "am I training today, and what is my weight doing".
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _weekOffset = 0;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final today = DateTime.now();
    final routine = effectiveRoutine(s, todayISO());
    final todayOverridden = s.dayPlan.containsKey(todayISO());
    final bw = lastBW(s);
    final prevBW = s.bodyweight.length > 1 ? s.bodyweight[s.bodyweight.length - 2] : null;
    final delta = bw != null && prevBW != null ? bw.w - prevBW.w : null;

    return AppPage(
      children: [
        PageHeader(
          title: 'My Wellness',
          subtitle: DateFormat('EEEE, d MMMM', dateLocale).format(today),
          trailing: IconButtonRound('gear', onTap: () => context.go('/settings')),
        ),
        // Today first — the one question this screen exists to answer — then a scannable
        // week-in-review, then the trends worth a longer look. Same order for training and
        // food throughout, so the screen reads as two parallel tracks rather than a training
        // page with a nutrition card wedged into it.
        _weekCard(context, s, today, routine, todayOverridden),
        if (s.routines.isEmpty && s.active == null) _welcomeCard(context),
        _todayNutritionCard(context, s),
        _snapshotGrid(context, ref, s, bw, delta),
        _bodyWeightCard(context, s, bw, delta),
        _nutritionTrendCard(context, s),
      ],
    );
  }

  /// Today's calories and macros, and a way in.
  ///
  /// Only appears once there is a profile to estimate from. An empty card inviting setup would
  /// be on this screen forever for everyone who does not want the feature, and Home is the one
  /// screen that has to stay about training.
  ///
  /// The ring answers "how much is left"; the bars answer "of what" — together they are the
  /// same glance a plain kcal count used to take two taps to get to.
  Widget _todayNutritionCard(BuildContext context, AppState s) {
    final c = context.c;
    final target = macroTargets(s);
    if (target == null) return const SizedBox.shrink();

    final iso = todayISO();
    final eaten = dayTotals(s, iso);
    final dayTarget = macroTargets(s, iso: iso) ?? target;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Pressable(
            scale: 1,
            onTap: () => context.go('/nutrition'),
            child: Row(
              children: [
                Expanded(
                  child: Text(t('Today\'s food'),
                      style: ts(TypeScale.foot, color: c.label2)),
                ),
                Text(
                  '${eaten.kcal.round()} / ${dayTarget.kcal.round()} ${t('kcal')}',
                  style: ts(TypeScale.foot, color: c.label, weight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                AppIcon('chevronRight', size: 14, color: c.label3),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              KcalRing(eaten: eaten.kcal, target: dayTarget.kcal, size: 84),
              const SizedBox(width: 18),
              Expanded(child: MacroBars(eaten: eaten, target: dayTarget, compact: true)),
            ],
          ),
        ],
      ),
    );
  }

  /// The week and the day, side by side: training done vs. planned, the current streak, the
  /// week's calorie budget, and where body weight stands — four numbers that used to take a
  /// full card each (or, for the budget, a trip to Nutrition) to see all at once.
  ///
  /// [StatTiles] and [calendarSheet] are the exact widget and the exact tap target the old
  /// streak-only card used; this grid replaces that card rather than adding to it.
  Widget _snapshotGrid(
      BuildContext context, WidgetRef ref, AppState s, BodyWeightEntry? bw, double? delta) {
    final c = context.c;
    final today = todayISO();
    final thisWeek = s.workouts.where((w) => weekKey(w.d) == weekKey(today)).length;
    final planned = s.week.values.where((v) => v.isNotEmpty).length;
    final budget = macroTargets(s) == null ? null : weekBudget(s, today);
    final weightColor =
        bw != null && delta != null ? bwDeltaColor(context, delta, bw.w, s.targetW) : null;

    return Pressable(
      scale: 1,
      onTap: calendarSheet,
      child: StatTiles(
        icons: const ['dumbbell', 'flame', 'meal', 'scale'],
        tiles: [
          (
            label: t('this week'),
            value: planned > 0 ? '$thisWeek/$planned' : '$thisWeek',
            unit: null,
            color: null,
          ),
          (label: t('Week streak'), value: '${streakWeeks(s)}', unit: null, color: null),
          (
            label: t('Eaten this week'),
            value: budget == null ? '—' : '${budget.spent.round()}/${budget.budget.round()}',
            unit: null,
            color: budget != null && budget.left < 0 ? c.sys.orange : null,
          ),
          (
            label: t('Body weight'),
            value: bw == null ? '—' : fmtNum(bw.w),
            unit: bw == null ? null : s.unit,
            color: weightColor,
          ),
        ],
      ),
    );
  }

  /// The week strip plus today's session, in one card — the two things the screen exists for.
  Widget _weekCard(
      BuildContext context, AppState s, DateTime today, Routine? routine, bool overridden) {
    final c = context.c;
    final monday = DateTime(
        today.year, today.month, today.day - ((jsDay(today) + 6) % 7) + _weekOffset * 7, 12);
    final sunday = DateTime(monday.year, monday.month, monday.day + 6, 12);
    final doneDays = {for (final w in s.workouts) w.d};

    // Finished, not in progress (s.active is cleared at finish). All of them, not the latest:
    // a day can hold several — a freestyle logged on top of the planned one — and the card
    // reports the day's total, so a two-a-day is no longer half invisible here.
    final doneToday = s.active == null ? workoutsOn(s, todayISO()) : const <Workout>[];

    final label = _weekOffset == 0
        ? t('This week')
        : '${monday.day} ${DateFormat.MMM(dateLocale).format(monday)} – '
            '${sunday.day} ${DateFormat.MMM(dateLocale).format(sunday)}';

    return AppCard(
      // This card is the call to action, so it wears the outline [AppCard.borderColor] is
      // reserved for — see the doc on that field. Once today is trained there is nothing left
      // to act on, so the outline drops away.
      borderColor: doneToday.isNotEmpty ? null : c.accLine,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButtonRound('chevronLeft',
                  size: 30, iconSize: 15, onTap: () => setState(() => _weekOffset--)),
              Expanded(
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: ts(TypeScale.foot, color: c.label2, weight: FontWeight.w500)),
              ),
              IconButtonRound('chevronRight',
                  size: 30, iconSize: 15, onTap: () => setState(() => _weekOffset++)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: _WeekDay(
                    date: DateTime(monday.year, monday.month, monday.day + i, 12),
                    state: s,
                    trained: doneDays,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _todayRow(context, s, routine, overridden, doneToday),
          if (doneToday.isNotEmpty) ...[
            const SizedBox(height: 10),
            Pressable(
              scale: 1,
              // These numbers are the day's, so a day with several sessions opens the recap that
              // lists them. Dropping into one session from a total would be pointing at the
              // wrong thing.
              onTap: () => doneToday.length == 1
                  ? workoutDetailSheet(doneToday.first)
                  : daySummarySheet(todayISO()),
              child:
                  StatTiles(icons: workoutStatIcons, tiles: dayStatTiles(doneToday, s)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _todayRow(BuildContext context, AppState s, Routine? routine, bool overridden,
      List<Workout> doneWorkouts) {
    final c = context.c;
    final active = s.active;
    final done = active == null && doneWorkouts.isNotEmpty;

    void onTap() {
      if (active != null) {
        context.go('/workout');
      } else if (done) {
        // Same rule as the tiles above: one session goes to it, several go to the day.
        doneWorkouts.length == 1
            ? workoutDetailSheet(doneWorkouts.first)
            : daySummarySheet(todayISO());
      } else if (routine != null) {
        startFlow(ref, routine.id);
      } else {
        dayOverrideSheet(todayISO());
      }
    }

    return Pressable.builder(
      scale: 1,
      onTap: onTap,
      build: (context, pressed) => AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: pressed ? c.surface3 : c.surface2,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Row(
          children: [
            GlyphTile(
              active != null
                  ? 'timer'
                  : (done ? 'check' : (routine != null ? glyphOf(routine.emoji) : 'moon')),
              background: active != null
                  ? c.sys.orange
                  : (done || routine != null ? c.acc : c.surface3),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t('Today').toUpperCase(),
                      style: ts(TypeScale.cap,
                          size: 11, color: c.label3, weight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(
                    active != null
                        ? t('{0} — in progress', active.name)
                        : (done
                            // One session is named; several are counted, because naming only
                            // the last one is how the second session went missing here.
                            ? (doneWorkouts.length == 1
                                ? doneWorkouts.first.name
                                : t('{0} sessions', doneWorkouts.length))
                            : (routine != null
                                ? '${routine.name}${overridden ? ' · ${t('rescheduled')}' : ''}'
                                : t('Rest day'))),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(TypeScale.body, color: c.label, weight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (active != null)
              Tag(t('Resume'),
                  capitalize: false,
                  color: c.sys.orange,
                  background: mixT(c.sys.orange, .16))
            else if (done)
              Tag(t('Done'),
                  icon: 'check',
                  capitalize: false,
                  color: c.acc,
                  background: c.accSoft)
            else if (routine != null)
              Tag(t('Start'), accent: true, capitalize: false)
            else
              AppIcon('plus', size: 15, color: c.label, stroke: 2.4),
          ],
        ),
      ),
    );
  }

  Widget _welcomeCard(BuildContext context) {
    final c = context.c;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            GlyphTile('sparkles'),
            const SizedBox(width: 10),
            Text(t('Welcome!'),
                style: ts(TypeScale.title2, color: c.label, weight: FontWeight.w600)),
          ]),
          const SizedBox(height: 6),
          Text(
            t('Set up your weekly routine to get going — or load a ready-made Push / Pull / Legs plan.'),
            style: ts(TypeScale.foot, color: c.label2),
          ),
          const SizedBox(height: 12),
          AppButton(t('Load starter plan (PPL)'),
              variant: BtnVariant.primary,
              icon: 'sparkles',
              onTap: () => loadStarterPlan(ref)),
          const SizedBox(height: 8),
          AppButton(t('Build my own plan'), onTap: () => context.go('/plan')),
        ],
      ),
    );
  }

  Widget _bodyWeightCard(
      BuildContext context, AppState s, BodyWeightEntry? bw, double? delta) {
    final c = context.c;
    final points = [
      for (final b in s.bodyweight.length > 30
          ? s.bodyweight.sublist(s.bodyweight.length - 30)
          : s.bodyweight)
        ChartPoint(t: b.t ?? dayOf(b.d).millisecondsSinceEpoch, y: b.w, d: b.d)
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text(t('Body weight'), style: ts(TypeScale.foot, color: c.label2)),
            ),
            AppButton(s.targetW != null ? fmtNum(s.targetW) : t('Goal'),
                size: BtnSize.sm,
                icon: 'target',
                color: s.targetW != null ? c.sys.yellow : null,
                onTap: goalSheet),
            const SizedBox(width: 8),
            AppButton(t('Log'), size: BtnSize.sm, icon: 'plus', onTap: () => bwSheet()),
          ]),
          const SizedBox(height: 6),
          if (bw == null)
            Text(
              t("No entries yet — log your weight to start the curve. It's also asked before every workout."),
              style: ts(TypeScale.foot, color: c.label2),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(fmtNum(bw.w),
                    style: ts(TypeScale.large,
                        size: 30, color: c.label, weight: FontWeight.w600)),
                const SizedBox(width: 4),
                Text(s.unit, style: ts(TypeScale.callout, color: c.label2)),
                // Only when it actually moved — an unchanged weight used to read as "− 0".
                if (delta != null && delta != 0) ...[
                  const SizedBox(width: 8),
                  AppIcon(delta > 0 ? 'arrowUp' : 'arrowDown',
                      size: 12, color: bwDeltaColor(context, delta, bw.w, s.targetW)),
                  const SizedBox(width: 2),
                  Text(fmtNum(delta.abs()),
                      style: ts(TypeScale.foot,
                          color: bwDeltaColor(context, delta, bw.w, s.targetW),
                          weight: FontWeight.w500)),
                ],
                const Spacer(),
                Text(fmtDate(bw.d, true), style: ts(TypeScale.foot, color: c.label3)),
              ],
            ),
            if (s.targetW != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  AppIcon('target', size: 13, color: c.sys.yellow),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      '${t('Goal')} ${fmtNum(s.targetW)} ${s.unit} · '
                      '${(s.targetW! - bw.w).abs() < 0.05 ? t('reached!') : t(s.targetW! > bw.w ? '{0} to gain' : '{0} to lose', '${fmtNum((s.targetW! - bw.w).abs())} ${s.unit}')}',
                      style: ts(TypeScale.foot, color: c.sys.yellow),
                    ),
                  ),
                ]),
              ),
            const SizedBox(height: 8),
            LineChart(points: points, height: 130, unit: s.unit, goal: s.targetW),
          ],
        ],
      ),
    );
  }

  /// Calories over the last two weeks against target, plus the week's macro averages.
  ///
  /// The old nutrition card carried this chart too, squeezed under the macro bars; giving it
  /// its own card is what makes room for the ring above, and lets it stand as the thing this
  /// screen was missing — a trend for food the way the chart below is already a trend for
  /// weight.
  Widget _nutritionTrendCard(BuildContext context, AppState s) {
    final c = context.c;
    final target = macroTargets(s);
    if (target == null) return const SizedBox.shrink();

    final today = todayISO();
    final days = <String>{for (final m in s.meals) m.d}.toList()..sort();
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    final points = <ChartPoint>[
      for (final d in days)
        if (!dayOf(d).isBefore(cutoff))
          ChartPoint(t: dayOf(d).millisecondsSinceEpoch, y: dayTotals(s, d).kcal, d: d),
    ];
    if (points.isEmpty) return const SizedBox.shrink();

    final budget = weekBudget(s, today);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t('Nutrition'), style: ts(TypeScale.foot, color: c.label2)),
              ),
              Text(
                '${budget.spent.round()} / ${budget.budget.round()} ${t('kcal')}',
                style: ts(TypeScale.foot, color: c.label2),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LineChart(points: points, height: 110, unit: t('kcal'), goal: target.kcal),
          const SizedBox(height: 10),
          MacroLegend(macros: weekMacros(s, today)),
        ],
      ),
    );
  }
}

/// One day of the week strip: its letter, its number, and a dot that says what it holds.
class _WeekDay extends ConsumerWidget {
  const _WeekDay({required this.date, required this.state, required this.trained});

  final DateTime date;
  final AppState state;
  final Set<String> trained;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final iso = isoOf(date);
    final isToday = iso == todayISO();
    final planned = effectiveRoutineId(state, iso);
    final overridden = state.dayPlan.containsKey(iso);
    final done = trained.contains(iso);
    final dayWorkouts = workoutsOn(state, iso);

    final dot = done
        ? c.acc
        : (overridden && planned != null
            ? c.sys.orange
            : (planned != null ? c.label3 : Colors.transparent));

    return Pressable.builder(
      scale: 1,
      // A day that was trained opens its recap — the day's totals, its sessions, and the
      // nutrition and weigh-in logged against it. A single session no longer short-circuits
      // past that: it is one row in the recap, one tap from its own detail, and going straight
      // there is what made a normal training day's macros and body weight unreachable.
      // An untrained day is still planned rather than reviewed, past excepted.
      onTap: () => dayWorkouts.isNotEmpty || iso.compareTo(todayISO()) < 0
          ? daySummarySheet(iso)
          : dayOverrideSheet(iso),
      build: (context, pressed) => AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 9),
        decoration: BoxDecoration(
          color: pressed ? c.surface2 : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(t(days[jsDay(date)]).toUpperCase(),
                style: ts(TypeScale.cap,
                    size: 11, color: c.label3, weight: FontWeight.w500)),
            const SizedBox(height: 4),
            SizedBox(
              height: 31,
              child: isToday
                  ? Container(
                      width: 31,
                      height: 31,
                      decoration: BoxDecoration(color: c.acc, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text('${date.day}',
                          style: ts(TypeScale.body,
                              color: c.onAcc, weight: FontWeight.w600)),
                    )
                  : Center(
                      child: Text('${date.day}', style: ts(TypeScale.body, color: c.label))),
            ),
            const SizedBox(height: 4),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}
