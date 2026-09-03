import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_state.dart';
import '../../domain/format.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../domain/nutrition.dart';
import '../../state/app_state_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/macro_bar.dart';
import '../widgets/page.dart';
import 'plan_sheets.dart';
import 'sheet_service.dart';
import 'workout_flow.dart';

/// The month view.
///
/// Every day is reachable: a trained day opens what you did, and any other day opens the
/// planner — so the calendar is both the history and the way to reschedule, rather than a
/// read-only decoration.
Future<void> calendarSheet([String? startIso]) =>
    showSheet<void>((context, close) => _Calendar(startIso: startIso, close: close));

class _Calendar extends ConsumerStatefulWidget {
  const _Calendar({required this.startIso, required this.close});

  final String? startIso;
  final void Function([void]) close;

  @override
  ConsumerState<_Calendar> createState() => _CalendarState();
}

class _CalendarState extends ConsumerState<_Calendar> {
  late DateTime _cursor = widget.startIso != null
      ? DateTime(dayOf(widget.startIso!).year, dayOf(widget.startIso!).month)
      : DateTime(DateTime.now().year, DateTime.now().month);

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final y = _cursor.year;
    final mo = _cursor.month;

    final byDay = <String, List<Workout>>{};
    for (final w in s.workouts) {
      byDay.putIfAbsent(w.d, () => []).add(w);
    }

    // Monday-first grid.
    final startOffset = (jsDay(DateTime(y, mo, 1, 12)) + 6) % 7;
    final daysIn = DateTime(y, mo + 1, 0).day;
    final prefix = '$y-${mo.toString().padLeft(2, '0')}';
    final monthWorkouts = s.workouts.where((w) => w.d.startsWith(prefix)).toList();
    final monthVol = monthWorkouts.fold(0.0, (a, w) => a + (w.vol ?? 0));
    final monthMs = monthWorkouts.fold(
        0, (a, w) => a + ((w.end == 0 ? w.start : w.end) - w.start).clamp(0, 1 << 40));

    final cells = <Widget>[
      for (var i = 0; i < startOffset; i++) const SizedBox.shrink(),
    ];
    for (var d = 1; d <= daysIn; d++) {
      final iso = '$prefix-${d.toString().padLeft(2, '0')}';
      final ws = byDay[iso];
      final effId = effectiveRoutineId(s, iso);
      final overridden = s.dayPlan.containsKey(iso);
      final dot = ws != null
          ? c.acc
          : (overridden && effId != null
              ? c.sys.orange
              : (effId != null ? c.label3 : Colors.transparent));

      cells.add(GestureDetector(
        onTap: () {
          widget.close();
          if (iso.compareTo(todayISO()) < 0) {
            // A past day cannot be planned, only reviewed — ISO date strings sort by date.
            daySummarySheet(iso);
          } else if (ws == null) {
            dayOverrideSheet(iso);
          } else if (ws.length == 1) {
            workoutDetailSheet(ws.first);
          } else {
            showSheet<void>((ctx, close2) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SheetTitle(fmtDate(iso, true)),
                    AppList(children: [
                      for (final w in ws)
                        WorkoutRow(
                          workout: w,
                          onTap: () {
                            close2();
                            workoutDetailSheet(w);
                          },
                        ),
                    ]),
                    const SizedBox(height: 8),
                  ],
                ));
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: ws != null ? c.accSoft : c.surface,
            borderRadius: BorderRadius.circular(10),
            border: iso == todayISO() ? Border.all(color: c.acc, width: 1.8) : null,
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$d',
                  style: ts(TypeScale.sub, color: ws != null ? c.acc : c.label)),
              const SizedBox(height: 3),
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
            ],
          ),
        ),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          IconButtonRound('chevronLeft',
              onTap: () => setState(() => _cursor = DateTime(y, mo - 1))),
          Expanded(
            child: Text('${t(monthsLong[mo - 1])} $y',
                textAlign: TextAlign.center,
                style: ts(TypeScale.title2, color: c.label, size: 20, weight: FontWeight.w600)),
          ),
          IconButtonRound('chevronRight',
              onTap: () => setState(() => _cursor = DateTime(y, mo + 1))),
        ]),
        const SizedBox(height: 4),
        Text(
          monthWorkouts.isEmpty
              ? t('No workouts this month')
              : '${t(monthWorkouts.length == 1 ? '{0} workout' : '{0} workouts', monthWorkouts.length)}'
                  ' · ${fmtDur(monthMs)} · ${fmtVol(monthVol, s.unit)}',
          textAlign: TextAlign.center,
          style: ts(TypeScale.foot, color: c.label2),
        ),
        const SizedBox(height: 10),
        Row(children: [
          for (final l in ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'])
            Expanded(
              child: Text(t(l).toUpperCase(),
                  textAlign: TextAlign.center,
                  style: ts(TypeScale.cap,
                      size: 11, color: c.label3, weight: FontWeight.w500)),
            ),
        ]),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 5,
          crossAxisSpacing: 5,
          children: cells,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LegendDot(color: c.acc, label: t('Trained')),
            const SizedBox(width: 14),
            _LegendDot(color: c.label3, label: t('Planned')),
            const SizedBox(width: 14),
            _LegendDot(color: c.sys.orange, label: t('Rescheduled')),
          ],
        ),
        const SizedBox(height: 10),
        Text(t('Tap a past day for its recap · tap a future day to plan a session'),
            textAlign: TextAlign.center, style: ts(TypeScale.foot, color: c.label3)),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// A read-only recap of one past day: what was planned and whether it was trained, the
/// nutrition logged that day, and the body weight if there was a weigh-in. Opened from the
/// calendar for any date before today — the past can be reviewed, not planned.
Future<void> daySummarySheet(String iso) =>
    showSheet<void>((context, close) => _DaySummary(iso: iso, close: close));

class _DaySummary extends ConsumerWidget {
  const _DaySummary({required this.iso, required this.close});

  final String iso;
  final void Function([void]) close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);

    final ws = s.workouts.where((w) => w.d == iso).toList();
    final effId = effectiveRoutineId(s, iso);
    Routine? planned;
    for (final r in s.routines) {
      if (r.id == effId) planned = r;
    }
    final status = ws.isNotEmpty
        ? t('Trained')
        : (planned != null ? t('Missed') : t('Rest day'));

    final target = macroTargets(s);
    final eaten = dayTotals(s, iso);

    double? bw;
    for (final b in s.bodyweight) {
      if (b.d == iso) bw = b.w;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(fmtDate(iso, true)),
        Text([planned?.name ?? t('Rest'), status].join(' · '),
            style: ts(TypeScale.foot, color: c.label2)),
        const SizedBox(height: 12),
        if (ws.isNotEmpty)
          AppList(children: [
            for (final w in ws)
              WorkoutRow(
                workout: w,
                onTap: () {
                  close();
                  workoutDetailSheet(w);
                },
              ),
          ]),
        if (target != null) ...[
          if (ws.isNotEmpty) const SizedBox(height: 6),
          Text(t('Nutrition'), style: ts(TypeScale.foot, color: c.label2)),
          const SizedBox(height: 10),
          Row(children: [
            KcalRing(
                eaten: eaten.kcal,
                target: (macroTargets(s, iso: iso) ?? target).kcal,
                size: 84),
            const SizedBox(width: 18),
            Expanded(
              child: MacroBars(
                  eaten: eaten,
                  target: macroTargets(s, iso: iso) ?? target,
                  compact: true),
            ),
          ]),
        ],
        if (bw != null) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: Text(t('Body weight'),
                    style: ts(TypeScale.foot, color: c.label2))),
            Text('${fmtNum(bw)} ${s.unit}',
                style: ts(TypeScale.body, color: c.label, weight: FontWeight.w600)),
          ]),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: ts(TypeScale.cap, color: context.c.label3)),
        ],
      );
}
