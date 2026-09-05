import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_state.dart';
import '../../domain/format.dart';
import '../../domain/glyphs.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../domain/progression.dart';
import '../../state/app_state_provider.dart';
import '../app.dart';
import 'exercise_block.dart';
import '../sheets/exercise_sheets.dart';
import '../sheets/routine_sheets.dart';
import '../sheets/sheet_service.dart';
import '../sheets/workout_flow.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/media.dart';
import '../widgets/page.dart';

/// Either the chooser or the session — the route is the same, because "the workout" is one
/// place whether or not one is running.
class WorkoutScreen extends ConsumerWidget {
  const WorkoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(appStateProvider.select((s) => s.active != null));
    return active ? const _ActiveWorkout() : const _StartChooser();
  }
}

/* ------------------------------------------------------------------- chooser -- */

class _StartChooser extends ConsumerWidget {
  const _StartChooser();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final todayR = effectiveRoutine(s, todayISO());
    final overridden = s.dayPlan.containsKey(todayISO());
    final others = s.routines.where((r) => r.id != todayR?.id).toList();

    return AppPage(
      children: [
        PageHeader(
          title: t('Start workout'),
          subtitle: '${t(dayn[jsDay(DateTime.now())])} — '
              '${todayR != null ? t('today is {0}', todayR.name) : t('rest day, but no one’s stopping you')}',
        ),
        if (todayR != null)
          AppCard(
            borderColor: c.acc,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "${t("Today's plan")}${overridden ? ' · ${t('rescheduled')}' : ''}",
                  style: ts(TypeScale.foot, color: c.acc),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(todayR.name,
                            style: ts(TypeScale.large,
                                size: 30, color: c.label, weight: FontWeight.w600)),
                        Text(exCount(todayR.ex.length),
                            style: ts(TypeScale.foot, color: c.label2)),
                      ],
                    ),
                  ),
                  GlyphTile(glyphOf(todayR.emoji), size: 38, radius: 9),
                ]),
                const SizedBox(height: 12),
                AppButton(t('Start {0}', todayR.name),
                    variant: BtnVariant.primary,
                    icon: 'play',
                    onTap: () => startFlow(ref, todayR.id)),
              ],
            ),
          ),
        if (others.isNotEmpty) ...[
          SecHeading(t('Other routines')),
          AppList(children: [
            for (final r in others)
              ListItem(
                leading: GlyphTile(glyphOf(r.emoji)),
                onTap: () => startFlow(ref, r.id),
                trailing: [Tag(t('Start'), accent: true, capitalize: false)],
                child: ItemText(r.name, subtitle: exCount(r.ex.length)),
              ),
          ]),
        ],
        const SizedBox(height: 14),
        AppButton(t('Freestyle workout (pick as you go)'),
            icon: 'shuffle', onTap: () => startFlow(ref, null)),
        if (s.routines.isEmpty) ...[
          const SizedBox(height: 10),
          AppButton(t('Build a plan first'),
              variant: BtnVariant.primary, onTap: () => context.go('/plan')),
        ],
      ],
    );
  }
}

/* -------------------------------------------------------------------- active -- */

class _ActiveWorkout extends ConsumerWidget {
  const _ActiveWorkout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final a = s.active;
    if (a == null) return const SizedBox.shrink();

    final units = supersetUnits(a.entries);
    final cur = a.cur.clamp(0, a.entries.isEmpty ? 0 : a.entries.length - 1);
    final unit = a.entries.isEmpty ? <int>[] : unitOf(units, cur);
    final unitIdx = units.indexWhere((u) => _sameUnit(u, unit));
    final isSuperset = unit.length > 1;

    final total = a.entries.fold(0, (n, e) => n + e.sets.length);
    final done = setsDoneActive(a);
    final exDone = a.entries.where((e) => e.sets.isNotEmpty && e.sets.every((x) => x.done)).length;
    final allDone = a.entries.isNotEmpty && exDone == a.entries.length;

    return AppPage(
      children: [
        PageHeader(
          title: a.name,
          titleWidget: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(a.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(TypeScale.body, color: c.label, weight: FontWeight.w600)),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Elapsed(start: a.start),
                  Text(' · ${t('{0} sets', '$done/$total')}',
                      style: ts(TypeScale.sub, color: c.label2)),
                ],
              ),
            ],
          ),
          leading: IconButtonRound('xmark', onTap: () {
            confirmSheet(
              title: t('Discard workout?'),
              message: t('The sets you logged in this session will be lost.'),
              confirmText: t('Discard'),
              danger: true,
              onConfirm: () {
                ref.read(appStateProvider.notifier).update((st) => st.active = null);
                ref.read(uiProvider).stopRest();
                appNavigatorKey.currentContext?.go('/home');
              },
            );
          }),
          trailing: IconButtonRound('check',
              color: c.acc, onTap: () => finishWorkout(ref)),
        ),
        // Progress across the whole session, in sets — the unit the work is actually done in.
        Container(
          height: 4,
          margin: const EdgeInsets.only(bottom: 16),
          decoration:
              BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(99)),
          clipBehavior: Clip.antiAlias,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: total == 0 ? 0 : done / total,
              child: AnimatedContainer(
                duration: Motion.med,
                decoration:
                    BoxDecoration(color: c.acc, borderRadius: BorderRadius.circular(99)),
              ),
            ),
          ),
        ),
        if (a.entries.isEmpty)
          EmptyState(icon: 'shuffle', message: t('Freestyle workout — add your first exercise.'))
        else ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              isSuperset
                  ? t('Superset {0} / {1}', unitIdx + 1, units.length)
                  : t('Exercise {0} / {1}', unitIdx + 1, units.length),
              style: ts(TypeScale.foot, color: c.label2),
            ),
          ),
          if (isSuperset)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(R.lg),
                border: Border.all(color: c.accLine, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    AppIcon('link', size: 13, color: c.acc),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(t('Superset · do these back-to-back, rest after both'),
                          textAlign: TextAlign.center,
                          style: ts(TypeScale.cap, color: c.acc, weight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  for (var k = 0; k < unit.length; k++) ...[
                    if (k > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 14, 0, 8),
                        child: Text('+',
                            textAlign: TextAlign.center,
                            style: ts(TypeScale.sub, color: c.acc, weight: FontWeight.w600)),
                      ),
                    ExerciseBlock(entryIndex: unit[k], compact: true),
                  ],
                ],
              ),
            )
          else
            ExerciseBlock(entryIndex: cur),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: AppButton(t('Prev'),
                icon: 'chevronLeft',
                enabled: unitIdx > 0,
                onTap: unitIdx > 0
                    ? () => ref
                        .read(appStateProvider.notifier)
                        .update((st) => st.active!.cur = units[unitIdx - 1].first)
                    : null),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: AppButton(t('Next'),
                trailingIcon: 'chevronRight',
                enabled: unitIdx >= 0 && unitIdx < units.length - 1,
                onTap: (unitIdx >= 0 && unitIdx < units.length - 1)
                    ? () => ref
                        .read(appStateProvider.notifier)
                        .update((st) => st.active!.cur = units[unitIdx + 1].first)
                    : null),
          ),
        ]),
        const SizedBox(height: 10),
        AppButton(t('Add exercise'), icon: 'plus', onTap: () {
          final routine = s.routines.where((r) => r.id == a.routineId).firstOrNull;
          exercisePicker((ex) => exConfigSheet(
                ex: ex,
                routine: routine,
                onSave: (cfg) {
                  ref.read(appStateProvider.notifier).update((st) {
                    final full = cfg.copy()..id = ex.id;
                    final r = st.routines.where((x) => x.id == st.active!.routineId).firstOrNull;
                    final plan = nextPrescription(st, full, r);
                    st.active!.entries.add(WorkoutEntry(
                      id: ex.id,
                      target: cfg.copy(),
                      plan: plan,
                      sets: applyPrescription(buildSets(st, full), plan),
                    ));
                    st.active!.cur = st.active!.entries.length - 1;
                  });
                  ref.read(uiProvider).toast(t('Added {0}', capitalized(ex.n)));
                },
              ));
        }),
        const SizedBox(height: 10),
        AppButton(
          allDone
              ? t('Finish workout')
              : t('Finish workout early · {0} exercises', '$exDone/${a.entries.length}'),
          variant: allDone ? BtnVariant.primary : BtnVariant.ghost,
          color: allDone ? null : c.label3,
          onTap: () => finishWorkout(ref),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  static bool _sameUnit(List<int> a, List<int> b) =>
      a.length == b.length && a.first == (b.isEmpty ? -1 : b.first);
}

/// The elapsed clock, isolated so the workout tree does not rebuild every second.
class _Elapsed extends StatefulWidget {
  const _Elapsed({required this.start});

  final int start;

  @override
  State<_Elapsed> createState() => _ElapsedState();
}

class _ElapsedState extends State<_Elapsed> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    // A periodic timer that outlives its widget keeps the isolate awake and the clock running
    // for a session that has already ended.
    _tick?.cancel();
    super.dispose();
  }

  /// Read off the wall clock, not off a tick count, so the number is right after the app has
  /// been backgrounded for a while.
  String _label() {
    final s = ((DateTime.now().millisecondsSinceEpoch - widget.start) / 1000).floor();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) =>
      Text(_label(), style: ts(TypeScale.sub, color: context.c.label2));
}
