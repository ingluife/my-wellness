import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_state.dart';
import '../../domain/exercises.dart';
import '../../domain/format.dart';
import '../../domain/glyphs.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../domain/muscles.dart';
import '../../domain/nutrition.dart';
import '../../domain/onerm.dart';
import '../../domain/progression.dart';
import '../../state/app_state_provider.dart';
import '../app.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/body_map.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/media.dart';
import 'sheet_service.dart';
import 'weight_sheets.dart';

/// Starting a workout weighs you in first, then builds the session.
///
/// The order matters: the weigh-in is the one measurement that has to happen *before* the
/// training rather than after it, and asking for it here is what keeps the body-weight curve
/// honest without a separate habit to remember.
void startFlow(WidgetRef ref, String? routineId) {
  bwSheet(required: true, onDone: (bw) => beginWorkout(ref, routineId, bw));
}

/// Build the session and open it.
///
/// The prescription is applied as the session is built, so you walk up to the bar with the
/// right weight already on screen instead of being told about it afterwards. `plan` is kept on
/// the entry purely so the workout can explain the number it chose.
void beginWorkout(WidgetRef ref, String? routineId, double? bw) {
  final s = ref.read(appStateProvider);
  final r = routineId == null
      ? null
      : s.routines.where((x) => x.id == routineId).firstOrNull;

  final entries = <WorkoutEntry>[];
  for (final cfg in r?.ex ?? const <ExerciseConfig>[]) {
    final plan = nextPrescription(s, cfg, r);
    entries.add(WorkoutEntry(
      id: cfg.id ?? '',
      sg: cfg.sg,
      target: cfg.copy(),
      plan: plan,
      sets: applyPrescription(buildSets(s, cfg), plan),
    ));
  }

  ref.read(appStateProvider.notifier).update((st) {
    st.active = ActiveWorkout(
      id: uid(),
      d: todayISO(),
      start: DateTime.now().millisecondsSinceEpoch,
      routineId: routineId,
      name: r?.name ?? t('Freestyle'),
      bw: bw,
      entries: entries,
    );
  });
  ref.read(uiProvider).stopRest();
  appNavigatorKey.currentContext?.go('/workout');
}

/// Confirm the working weight after finishing an exercise.
///
/// Your highest becomes the default next time, so this is the one number that carries forward
/// even when the sets themselves were messy. On the last superset unit it chains straight into
/// the finish prompt, which is why it takes the whole workout's shape into account.
Future<void> topWeightSheet(WidgetRef ref, int entryIndex) =>
    showSheet<void>((context, close) => _TopWeight(entryIndex: entryIndex, close: close));

class _TopWeight extends ConsumerStatefulWidget {
  const _TopWeight({required this.entryIndex, required this.close});

  final int entryIndex;
  final void Function([void]) close;

  @override
  ConsumerState<_TopWeight> createState() => _TopWeightState();
}

class _TopWeightState extends ConsumerState<_TopWeight> {
  double? _v;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final a = s.active;
    // The workout can end underneath this sheet: finishing from the last exercise clears
    // `active`, and this rebuilds before the sheet is torn down. Everything below is read
    // defensively and the sheet dismisses itself.
    final entry = (a != null && widget.entryIndex < a.entries.length)
        ? a.entries[widget.entryIndex]
        : null;
    final ex = entry == null ? null : exdb[entry.id];
    if (entry == null || ex == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.close());
      return const SizedBox.shrink();
    }

    final maxSet = entry.sets
        .where((x) => x.done)
        .fold(0.0, (m, x) => m > (x.w ?? 0) ? m : (x.w ?? 0));
    final prevBest = [
      s.exWeights[entry.id]?.w ?? 0,
      bestWeightFor(s, entry.id),
    ].reduce((x, y) => x > y ? x : y);
    final v = _v ??= (maxSet > prevBest ? maxSet : prevBest) > 0
        ? (maxSet > prevBest ? maxSet : prevBest)
        : (entry.target?.weight ?? 0);

    final units = supersetUnits(a!.entries);
    final unit = unitOf(units, widget.entryIndex);
    final unitDone = unit.every((i) => a.entries[i].sets.every((x) => x.done));
    final unitIdx = units.indexWhere((u) => u.contains(widget.entryIndex));
    final isLastUnit = unitIdx == units.length - 1;

    void commit(bool advance) {
      final n = ((v) * 10).round() / 10;
      if (!n.isFinite || n < 0) {
        ref.read(uiProvider).toast(t('Enter a valid weight'));
        return;
      }
      ref.read(appStateProvider.notifier).update((st) {
        final e = st.active!.entries[widget.entryIndex];
        e.topW = n;
        e.writesTopW = true;
        final cur = st.exWeights[entry.id];
        st.exWeights[entry.id] =
            ExWeight(w: cur != null && cur.w > n ? cur.w : n, d: todayISO());
      });
      widget.close();
      if (advance && unitDone) {
        if (isLastUnit) {
          workoutCompleteSheet(ref);
        } else {
          ref.read(appStateProvider.notifier).update((st) {
            st.active!.cur = units[unitIdx + 1].first;
          });
        }
      } else {
        final kept = ref.read(appStateProvider).exWeights[entry.id]?.w ?? n;
        ref.read(uiProvider)
            .toast(t('Tracked — next time starts at {0}', '${fmtNum(kept)} ${s.unit}'));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(
          t('{0} done', capitalized(ex.n)),
          leading: AppIcon('checkCircle', size: 22, color: c.acc),
        ),
        Text(
          t('Confirm the weight you worked with — your highest becomes the default next time.') +
              (!unitDone && unit.length > 1 ? ' ${t('Then finish the superset partner.')}' : ''),
          style: ts(TypeScale.foot, color: c.label2),
        ),
        WeightInput(value: v, unit: s.unit, onChanged: (x) => setState(() => _v = x)),
        const SizedBox(height: 10),
        if (prevBest > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${t('Previous best:')} ${fmtNum(prevBest)} ${s.unit}'),
                if (maxSet > prevBest)
                  TextSpan(
                    text: ' — ${t('new record!')}',
                    style: ts(TypeScale.foot, color: c.sys.yellow),
                  ),
              ]),
              textAlign: TextAlign.center,
              style: ts(TypeScale.foot, color: c.label3),
            ),
          )
        else
          const SizedBox(height: 4),
        if (unitDone) ...[
          AppButton(isLastUnit ? t('Save') : t('Save & next exercise'),
              variant: BtnVariant.primary,
              trailingIcon: isLastUnit ? null : 'chevronRight',
              onTap: () => commit(true)),
          const SizedBox(height: 8),
          AppButton(t('Just close'),
              variant: BtnVariant.ghost, color: c.label3, onTap: () => commit(false)),
        ] else
          AppButton(t('Save weight'), variant: BtnVariant.primary, onTap: () => commit(false)),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Shown when the last exercise's last set is checked — finish, or keep going.
Future<void> workoutCompleteSheet(WidgetRef ref) => showCenterSheet<void>((context, close) {
      final c = context.c;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: AppIcon('checkCircle', size: 44, color: c.acc)),
          const SizedBox(height: 8),
          Text(t("That's the whole workout!"),
              textAlign: TextAlign.center,
              style: ts(TypeScale.title2, color: c.label, size: 20, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            t('Every exercise done — great work. Finish up, or keep going and add another exercise.'),
            textAlign: TextAlign.center,
            style: ts(TypeScale.foot, color: c.label2),
          ),
          const SizedBox(height: 16),
          AppButton(t('Finish workout'), variant: BtnVariant.primary, icon: 'flag', onTap: () {
            close();
            finishWorkout(ref);
          }),
          const SizedBox(height: 8),
          AppButton(t('Continue workout'), onTap: () {
            close();
            ref.read(uiProvider).toast(t('Keep going — tap “+ Add exercise” below'));
          }),
        ],
      );
    });

/// Finish the session, asking first if it is not actually finished.
void finishWorkout(WidgetRef ref) {
  final a = ref.read(appStateProvider).active;
  if (a == null) return;
  final done = setsDoneActive(a);
  final total = a.entries.fold(0, (n, e) => n + e.sets.length);

  if (done == 0) {
    confirmSheet(
      title: t('Nothing logged yet'),
      message: t('You haven’t checked off any sets. Finish the workout anyway?'),
      confirmText: t('Finish anyway'),
      onConfirm: () => _doFinishWorkout(ref),
    );
    return;
  }
  if (done < total) {
    final left = total - done;
    confirmSheet(
      title: t('Finish early?'),
      message: t(
          left == 1
              ? '{0} set still unchecked. Finish the workout now?'
              : '{0} sets still unchecked. Finish the workout now?',
          left),
      confirmText: t('Finish workout'),
      onConfirm: () => _doFinishWorkout(ref),
    );
    return;
  }
  _doFinishWorkout(ref);
}

void _doFinishWorkout(WidgetRef ref) {
  final s = ref.read(appStateProvider);
  final a = s.active;
  if (a == null) return;

  final prs = <String>[];
  final e1prs = <({String id, double est})>[];
  for (final e in a.entries) {
    final mx = e.sets.where((x) => x.done).fold(0.0, (m, x) => m > (x.w ?? 0) ? m : (x.w ?? 0));
    if (mx > 0 && mx > bestWeightFor(s, e.id)) prs.add(e.id);
    // A heavier estimate without a heavier top set is its own kind of progress — same weight
    // for more reps. Reported separately so it cannot be read as a load PR.
    final rec = is1RMRecord(s, e.id, e);
    if (rec != null && !prs.contains(e.id)) e1prs.add((id: e.id, est: rec.est));
  }

  final w = Workout(
    id: a.id,
    d: a.d,
    start: a.start,
    end: DateTime.now().millisecondsSinceEpoch,
    routineId: a.routineId,
    name: a.name,
    bw: a.bw,
    prs: prs,
    // `target` is kept alongside the sets: without it a finished workout cannot say whether it
    // hit its reps, and a timed session reads back as "0 reps". It is what the progression
    // engine works from.
    entries: [
      for (final e in a.entries)
        if (e.sets.any((x) => x.done))
          WorkoutEntry(
            id: e.id,
            sets: [for (final x in e.sets) x.copy()],
            topW: e.topW,
            writesTopW: true,
            target: e.target?.copy(),
            n: e.n,
          )
    ],
  );
  w.vol = workoutVolume(w);

  ref.read(appStateProvider.notifier).update((st) {
    for (final e in w.entries) {
      final mx = [
        ...e.sets.where((x) => x.done).map((x) => x.w ?? 0),
        e.topW ?? 0,
      ].fold(0.0, (m, x) => m > x ? m : x);
      if (mx > 0) {
        final cur = st.exWeights[e.id];
        if (cur == null || mx > cur.w) st.exWeights[e.id] = ExWeight(w: mx, d: w.d);
      }
    }
    st.workouts.add(w.copy());
    st.active = null;
  });

  ref.read(uiProvider).stopRest();
  ref.read(uiProvider).workoutDone(s.sound);
  showCenterSheet<void>(
    locked: true,
    (context, close) => _FinishSummary(workout: w, prs: prs, e1prs: e1prs, close: close),
  );
}

class _FinishSummary extends ConsumerWidget {
  const _FinishSummary({
    required this.workout,
    required this.prs,
    required this.e1prs,
    required this.close,
  });

  final Workout workout;
  final List<String> prs;
  final List<({String id, double est})> e1prs;
  final void Function([void]) close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: AppIcon('trophy', size: 44, color: c.acc)),
        const SizedBox(height: 8),
        Text(t('Workout complete!'),
            textAlign: TextAlign.center,
            style: ts(TypeScale.title2, color: c.label, size: 20, weight: FontWeight.w600)),
        const SizedBox(height: 12),
        StatTiles(tiles: [
          (label: t('Duration'), value: fmtDur(workout.end - workout.start), color: null),
          (label: t('Volume'), value: fmtVol(workout.vol, s.unit), color: null),
          (label: t('Sets'), value: '${setsDone(workout)}', color: null),
          // Burned, not PRs, when there is a body weight to work it out from — the estimate
          // is never more meaningful than in the minute the session ends. PRs keep the slot
          // otherwise, and they get their own lines below either way.
          if (_burn(s) != null)
            (label: t('Burned'), value: '${workoutBurn(workout, _burn(s)!).round()} ${t('kcal')}', color: null)
          else
            (label: t('PRs'), value: prs.isEmpty ? '—' : '${prs.length}', color: null),
        ]),
        if (prs.isNotEmpty || e1prs.isNotEmpty) ...[
          for (final id in prs)
            _PrLine(icon: 'trophy', text: '${t('New PR:')} ${capitalized(exdb.or(id).n)}'),
          for (final p in e1prs)
            _PrLine(
                icon: 'chartLine',
                text:
                    '${t('Best estimated 1RM:')} ${capitalized(exdb.or(p.id).n)} · ${fmtNum(p.est)} ${s.unit}'),
          const SizedBox(height: 12),
        ],
        Text(t('What you just trained'), style: ts(TypeScale.foot, color: c.label2)),
        const SizedBox(height: 8),
        BodyMap(load: loadOfWorkouts([workout]), body: s.body),
        const SizedBox(height: 14),
        AppButton(t('Nice!'), variant: BtnVariant.primary, onTap: () {
          close();
          appNavigatorKey.currentContext?.go('/home');
        }),
      ],
    );
  }
}

/// Body weight in kg, or null when there has never been a weigh-in.
double? _burn(AppState s) => bodyKg(s);

class _PrLine extends StatelessWidget {
  const _PrLine({required this.icon, required this.text});

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(children: [
        AppIcon(icon, size: 13, color: c.acc),
        const SizedBox(width: 5),
        Expanded(child: Text(text, style: ts(TypeScale.foot, color: c.acc))),
      ]),
    );
  }
}

/// A 2x2 (or 1x4) grid of headline numbers.
typedef StatTile = ({String label, String value, Color? color});

class StatTiles extends StatelessWidget {
  const StatTiles({super.key, required this.tiles, this.icons});

  final List<StatTile> tiles;
  final List<String>? icons;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Widget tile(int i) => Container(
          padding: const EdgeInsets.all(14),
          decoration:
              BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(R.card)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                if (icons != null) ...[
                  AppIcon(icons![i], size: 14, color: c.label),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(tiles[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(TypeScale.foot, color: c.label2)),
                ),
              ]),
              const SizedBox(height: 5),
              Text(tiles[i].value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(TypeScale.title,
                      size: 26, color: tiles[i].color ?? c.label, weight: FontWeight.w600)),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          for (var row = 0; row * 2 < tiles.length; row++) ...[
            if (row > 0) const SizedBox(height: 10),
            Row(children: [
              Expanded(child: tile(row * 2)),
              if (row * 2 + 1 < tiles.length) ...[
                const SizedBox(width: 10),
                Expanded(child: tile(row * 2 + 1)),
              ] else
                const Expanded(child: SizedBox.shrink()),
            ]),
          ],
        ],
      ),
    );
  }
}

/// One finished workout, as a list row. Shared by Stats, History and the calendar.
class WorkoutRow extends ConsumerWidget {
  const WorkoutRow({super.key, required this.workout, required this.onTap});

  final Workout workout;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final routine = s.routines.where((r) => r.id == workout.routineId).firstOrNull;
    return ListItem(
      leading: GlyphTile(glyphOf(routine?.emoji), size: 34, radius: 8),
      onTap: onTap,
      trailing: [
        if (workout.prs.isNotEmpty) PrBadge('${workout.prs.length} PR'),
        AppIcon('chevronRight', size: 15, color: c.label, stroke: 2.4),
      ],
      child: ItemText(
        workout.name,
        subtitle: [
          fmtDate(workout.d, true),
          ...durPart(workout.end - workout.start),
          t('{0} sets', setsDone(workout)),
          fmtVol(workout.vol, s.unit),
        ].join(' · '),
      ),
    );
  }
}

/// The yellow PR pill.
class PrBadge extends StatelessWidget {
  const PrBadge(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Tag(label,
        icon: 'trophy',
        capitalize: false,
        color: c.sys.yellow,
        background: mixT(c.sys.yellow, .18));
  }
}

/// One finished workout in full, with the option to remove it.
Future<void> workoutDetailSheet(Workout w) =>
    showSheet<void>((context, close) => _WorkoutDetail(workout: w, close: close));

class _WorkoutDetail extends ConsumerWidget {
  const _WorkoutDetail({required this.workout, required this.close});

  final Workout workout;
  final void Function([void]) close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    // The workout's own weigh-in when it has one — this is a look back at a session that may be
    // weeks old, so the live body weight would be the wrong number to cost it at.
    final kg = workout.bw != null ? kgOf(workout.bw!, s.unit) : bodyKg(s);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(workout.name),
        Text(
          [
            fmtDate(workout.d, true),
            ...durPart(workout.end - workout.start),
            fmtVol(workout.vol, s.unit),
            if (workout.bw != null) '${fmtNum(workout.bw)} ${s.unit}',
          ].join(' · '),
          style: ts(TypeScale.foot, color: c.label2),
        ),
        const SizedBox(height: 12),
        StatTiles(tiles: [
          (label: t('Duration'), value: fmtDur(workout.end - workout.start), color: null),
          (label: t('Volume'), value: fmtVol(workout.vol, s.unit), color: null),
          (label: t('Sets'), value: '${setsDone(workout)}', color: null),
          if (kg != null)
            (label: t('Burned'), value: '${workoutBurn(workout, kg).round()} ${t('kcal')}', color: null)
          else
            (label: t('PRs'), value: workout.prs.isEmpty ? '—' : '${workout.prs.length}', color: null),
        ]),
        for (final e in workout.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (exdb[e.id] != null) ...[
                  ExerciseThumb(ex: exdb[e.id]!),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(
                            capitalized(exdb[e.id]?.n ?? e.n ?? e.id),
                            style: ts(TypeScale.callout,
                                size: 16, color: c.label, weight: FontWeight.w600),
                          ),
                        ),
                        if (workout.prs.contains(e.id)) ...[
                          const SizedBox(width: 6),
                          const PrBadge('PR'),
                        ],
                      ]),
                      const SizedBox(height: 2),
                      Text(
                        e.sets
                                .where((x) => x.done)
                                .map((x) => setLabel(e.id, x, e.target))
                                .join('  ·  ')
                                .trim()
                                .isEmpty
                            ? t('no sets')
                            : e.sets
                                .where((x) => x.done)
                                .map((x) => setLabel(e.id, x, e.target))
                                .join('  ·  '),
                        style: ts(TypeScale.foot, color: c.label2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        AppButton(t('Delete workout'), variant: BtnVariant.danger, onTap: () {
          confirmSheet(
            title: t('Delete workout?'),
            message: t('This removes it from your history for good.'),
            confirmText: t('Delete'),
            danger: true,
            onConfirm: () {
              ref
                  .read(appStateProvider.notifier)
                  .update((st) => st.workouts.removeWhere((x) => x.id == workout.id));
              close();
              ref.read(uiProvider).toast(t('Workout deleted'));
            },
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}
