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
          title: 'openGym',
          subtitle: DateFormat('EEEE, d MMMM', dateLocale).format(today),
          trailing: IconButtonRound('gear', onTap: () => context.go('/settings')),
        ),
        _weekCard(context, s, today, routine, todayOverridden),
        if (s.routines.isEmpty && s.active == null) _welcomeCard(context),
        _bodyWeightCard(context, s, bw, delta),
        _nutritionCard(context, s),
        _streakCard(context, s),
      ],
    );
  }

  /// Today's calories, and a way in.
  ///
  /// Only appears once there is a profile to estimate from. An empty card inviting setup would
  /// be on this screen forever for everyone who does not want the feature, and Home is the one
  /// screen that has to stay about training.
  Widget _nutritionCard(BuildContext context, AppState s) {
    final c = context.c;
    final target = macroTargets(s);
    if (target == null) return const SizedBox.shrink();

    final iso = todayISO();
    final eaten = dayTotals(s, iso);
    final dayTarget = macroTargets(s, iso: iso) ?? target;

    // One point per day that has any food on it, over the last two weeks — a glance at trend
    // rather than the full history Stats already shows.
    final days = <String>{for (final m in s.meals) m.d}.toList()..sort();
    final cutoff = DateTime.now().subtract(const Duration(days: 14));
    final points = <ChartPoint>[
      for (final d in days)
        if (!dayOf(d).isBefore(cutoff))
          ChartPoint(t: dayOf(d).millisecondsSinceEpoch, y: dayTotals(s, d).kcal, d: d),
    ];

    return AppCard(
      // The chart below has its own gesture detector for its hover tooltip, so only the header
      // — not the whole card — navigates. A card-wide onTap around a LineChart would put the
      // two gestures in the same arena for no good reason.
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
          const SizedBox(height: 10),
          MacroBars(eaten: eaten, target: dayTarget, compact: true),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 10),
            LineChart(points: points, height: 90, unit: t('kcal'), goal: dayTarget.kcal),
          ],
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

    final label = _weekOffset == 0
        ? t('This week')
        : '${monday.day} ${DateFormat.MMM(dateLocale).format(monday)} – '
            '${sunday.day} ${DateFormat.MMM(dateLocale).format(sunday)}';

    return AppCard(
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
          _todayRow(context, s, routine, overridden),
        ],
      ),
    );
  }

  Widget _todayRow(BuildContext context, AppState s, Routine? routine, bool overridden) {
    final c = context.c;
    final active = s.active;

    void onTap() {
      if (active != null) {
        context.go('/workout');
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
              active != null ? 'timer' : (routine != null ? glyphOf(routine.emoji) : 'moon'),
              background: active != null
                  ? c.sys.orange
                  : (routine != null ? c.acc : c.surface3),
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
                        : (routine != null
                            ? '${routine.name}${overridden ? ' · ${t('rescheduled')}' : ''}'
                            : t('Rest day')),
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

  Widget _streakCard(BuildContext context, AppState s) {
    final c = context.c;
    final thisWeek = s.workouts.where((w) => weekKey(w.d) == weekKey(todayISO())).length;
    final planned = s.week.values.where((v) => v.isNotEmpty).length;
    return AppCard(
      onTap: () => calendarSheet(),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  AppIcon('flame', size: 22, color: c.sys.orange),
                  const SizedBox(width: 7),
                  Text(t('{0} week streak', streakWeeks(s)),
                      style: ts(TypeScale.title2, color: c.label, weight: FontWeight.w600)),
                ]),
                const SizedBox(height: 2),
                Text(
                  '$thisWeek${planned > 0 ? ' / $planned' : ''} ${t('this week')} · '
                  '${t(s.workouts.length == 1 ? '{0} workout total' : '{0} workouts total', s.workouts.length)}',
                  style: ts(TypeScale.foot, color: c.label2),
                ),
              ],
            ),
          ),
          AppIcon('calendar', size: 20, color: c.label),
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

    final dot = done
        ? c.acc
        : (overridden && planned != null
            ? c.sys.orange
            : (planned != null ? c.label3 : Colors.transparent));

    return Pressable.builder(
      scale: 1,
      onTap: () => dayOverrideSheet(iso),
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
