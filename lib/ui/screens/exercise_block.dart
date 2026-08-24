import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_state.dart';
import '../../domain/exercises.dart';
import '../../domain/format.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../state/app_state_provider.dart';
import '../app.dart';
import '../sheets/exercise_sheets.dart';
import '../sheets/workout_flow.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/stepper.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/controls/toggles.dart';
import '../widgets/media.dart';

/// One column of a set row.
typedef SetColumn = ({
  String field,
  double step,
  bool decimal,
  String heading,
  bool optional,
  String? effortScale,
});

/// One exercise inside a running workout: the animation, what it is, what you did last time,
/// why the numbers are what they are, and the set rows themselves.
class ExerciseBlock extends ConsumerWidget {
  const ExerciseBlock({super.key, required this.entryIndex, this.compact = false});

  final int entryIndex;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final a = s.active;
    if (a == null || entryIndex >= a.entries.length) return const SizedBox.shrink();

    final entry = a.entries[entryIndex];
    final ex = exdb.or(entry.id);
    final cfg = entry.cfg;
    final mode = modeOf(cfg);
    final cardio = mode == 'cardio';
    final timed = mode == 'time';
    final last = lastEntryFor(s, entry.id);

    // The same number the "confirm your working weight" sheet calls your best, so the two
    // never disagree inside one session.
    final best = cardio
        ? 0.0
        : [bestWeightFor(s, entry.id), s.exWeights[entry.id]?.w ?? 0]
            .reduce((x, y) => x > y ? x : y);

    // A bodyweight set has no weight to type, so the column is not there — one stepper instead
    // of two, which is the whole point of the flag. Adding a belt weight in the config brings
    // it back, now labelled as the addition it is.
    final bw = !cardio && isBw(cfg);
    final added = bw && entry.sets.any((x) => (x.w ?? 0) > 0);

    final loadCol = (
      field: 'w',
      step: 2.5,
      decimal: true,
      heading: bw ? t('Added ({0})', s.unit) : t('Weight ({0})', s.unit),
      optional: false,
      effortScale: null,
    );
    // The reps column is the total in every mode, unilateral included — the stepper walks in
    // twos there so the number you land on is one you can actually split evenly.
    final repCol = (
      field: 'r',
      step: repStep(cfg),
      decimal: false,
      heading: t('Reps'),
      optional: false,
      effortScale: null,
    );

    final SetColumn col1 = cardio
        ? (field: 'min', step: 1, decimal: false, heading: t('Duration (min)'), optional: false, effortScale: null)
        : timed
            ? (field: 'sec', step: 5, decimal: false, heading: t('Seconds'), optional: false, effortScale: null)
            : (bw && !added ? repCol : loadCol);

    final SetColumn? col2 = cardio
        ? (field: 'speed', step: 0.5, decimal: true, heading: t('Speed (km/h)'), optional: false, effortScale: null)
        : timed
            ? ((bw && !added) ? null : loadCol)
            : ((bw && !added) ? null : repCol);

    // Effort only makes sense for weighted rep sets, not cardio or timed holds, and is opt-in
    // since it adds a third stepper to every row. Optional, because an unlogged effort is not
    // the same as 0 — RIR 0 says the set went to failure.
    final kind = effortOf(s);
    final eff = effortScales[kind];
    final SetColumn? col3 = mode == 'reps' && eff != null
        ? (
            field: eff.f,
            step: eff.step,
            decimal: true,
            heading: t(eff.hd),
            optional: true,
            effortScale: kind,
          )
        : null;

    final plan = entry.plan;
    final showWhy = plan != null && plan.why != null && plan.kind != 'off';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExerciseMedia(ex: ex, compact: compact, minimizable: !compact),
        Row(children: [
          Expanded(
            child: Text(
              capitalized(ex.n),
              style: ts(TypeScale.title2,
                  size: compact ? 17 : 20, color: c.label, weight: FontWeight.w600),
            ),
          ),
          IconButtonRound('info', onTap: () => exerciseDetailSheet(ex)),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (cardio) Tag(t('Cardio'), icon: 'figureRun', accent: true),
          // You log the total; this is the split, so the set in front of you is unambiguous
          // without the rep count having to mean two different things.
          if (!cardio && !timed && isPerSide(cfg))
            Tag(
              t('{0} per side',
                  fmtNum(sideReps(
                      (entry.sets.where((x) => !x.done).firstOrNull ?? entry.sets.firstOrNull)?.r))),
              icon: 'shuffle',
              accent: true,
              capitalize: false,
            ),
          if (ex.tg.isNotEmpty || ex.bp.isNotEmpty)
            Tag(t(ex.tg.isNotEmpty ? ex.tg : ex.bp)),
          if (ex.eq.isNotEmpty) Tag(t(ex.eq)),
          if (best > 0) Tag('${t('Best:')} ${fmtNum(best)} ${s.unit}', capitalize: false),
        ]),
        if (last != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              '${t('Last time')} (${fmtDate(last.d)}): '
              '${last.sets.map((x) => setLabel(entry.id, x, last.target)).join(', ')}',
              style: ts(TypeScale.foot, color: c.label3),
            ),
          ),
        if (showWhy)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AppIcon(
                switch (plan.kind) {
                  'up' => 'arrowUp',
                  'deload' => 'arrowDown',
                  _ => 'lightbulb',
                },
                size: 14,
                color: plan.kind == 'deload' ? c.sys.yellow : c.acc,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(tList(plan.why!),
                    style: ts(TypeScale.foot,
                        color: plan.kind == 'deload' ? c.sys.yellow : c.acc)),
              ),
            ]),
          ),
        AppCard(
          margin: const EdgeInsets.only(top: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SetHeader(col1: col1, col2: col2, col3: col3, timed: timed),
              for (var i = 0; i < entry.sets.length; i++)
                _SetRow(
                  entryIndex: entryIndex,
                  setIndex: i,
                  col1: col1,
                  col2: col2,
                  col3: col3,
                  timed: timed,
                  first: i == 0,
                ),
              const SizedBox(height: 8),
              Row(children: [
                AppButton(t('Remove set'),
                    size: BtnSize.sm,
                    icon: 'minus',
                    enabled: entry.sets.length > 1,
                    onTap: () => ref.read(appStateProvider.notifier).update((st) {
                          final e = st.active!.entries[entryIndex];
                          if (e.sets.length > 1) e.sets.removeLast();
                        })),
                const SizedBox(width: 12),
                AppButton(t('Add set'),
                    size: BtnSize.sm, icon: 'plus', onTap: () => _addSet(ref)),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  /// A new set copies the last one, so adding a fourth set of the same thing is one tap.
  void _addSet(WidgetRef ref) => ref.read(appStateProvider.notifier).update((st) {
        final e = st.active!.entries[entryIndex];
        final l = e.sets.isEmpty ? null : e.sets.last;
        final m = modeOf(e.cfg);
        if (m == 'cardio') {
          e.sets.add(SetLog(
              min: l?.min ?? e.target?.min ?? 20, speed: l?.speed ?? e.target?.speed ?? 8));
        } else if (m == 'time') {
          e.sets.add(SetLog(
              sec: l?.sec ?? e.target?.sec ?? 45, w: l?.w ?? e.target?.weight ?? 0));
        } else {
          e.sets.add(SetLog(w: l?.w ?? 0, r: l?.r ?? e.target?.reps));
        }
      });
}

class _SetHeader extends StatelessWidget {
  const _SetHeader(
      {required this.col1, required this.col2, required this.col3, required this.timed});

  final SetColumn col1;
  final SetColumn? col2;
  final SetColumn? col3;
  final bool timed;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final style = ts(TypeScale.cap,
        size: 11, color: c.label3, weight: FontWeight.w500);
    Widget cell(int flex, String text) => Expanded(
          flex: flex,
          child: Text(text.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style),
        );
    // The header carries the same sizing as the rows, or the labels drift off their columns.
    final three = col3 != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        const SizedBox(width: 24),
        SizedBox(width: three ? 6 : 8),
        cell(three ? 12 : 14, col1.heading),
        if (col2 != null) ...[SizedBox(width: three ? 6 : 8), cell(10, col2!.heading)],
        if (col3 != null) ...[const SizedBox(width: 6), cell(9, col3!.heading)],
        if (timed) const SizedBox(width: 38),
        const SizedBox(width: 38),
      ]),
    );
  }
}

class _SetRow extends ConsumerWidget {
  const _SetRow({
    required this.entryIndex,
    required this.setIndex,
    required this.col1,
    required this.col2,
    required this.col3,
    required this.timed,
    required this.first,
  });

  final int entryIndex;
  final int setIndex;
  final SetColumn col1;
  final SetColumn? col2;
  final SetColumn? col3;
  final bool timed;
  final bool first;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final entry = s.active!.entries[entryIndex];
    final set = entry.sets[setIndex];
    final working = ref.watch(uiProvider).work != null;
    final three = col3 != null;

    Widget cell(SetColumn col, int flex) => Expanded(
          flex: flex,
          child: AppStepper(
            value: set.field(col.field),
            decimal: col.decimal,
            nullable: col.optional,
            step: col.step,
            buttonWidth: three ? (col.effortScale != null ? 20 : 23) : 32,
            buttonHeight: 40,
            fontSize: three ? 14 : null,
            // The effort column walks its own scale; weight and reps step up from 0 with no
            // ceiling, as they always did.
            onStep: col.effortScale == null
                ? null
                : (dir) => stepEffort(col.effortScale!, set.field(col.field), dir),
            onChanged: (v) => _setField(
                ref, col.field, col.effortScale == null ? v : capEffort(col.effortScale!, v)),
          ),
        );

    return Opacity(
      opacity: set.done ? .45 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: first
            ? null
            : BoxDecoration(
                border: Border(top: BorderSide(color: c.sep, width: R.hair)),
              ),
        child: Row(children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: set.done ? c.acc : c.surface2,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text('${setIndex + 1}',
                style: ts(TypeScale.cap,
                    color: set.done ? c.onAcc : c.label2, weight: FontWeight.w500)),
          ),
          SizedBox(width: three ? 6 : 8),
          cell(col1, three ? 12 : 14),
          if (col2 != null) ...[SizedBox(width: three ? 6 : 8), cell(col2!, 10)],
          if (col3 != null) ...[const SizedBox(width: 6), cell(col3!, 9)],
          // A timed set is started, not typed: the timer counts the hold down and checks the
          // set off itself. The checkbox stays for anyone who timed it on their own watch.
          if (timed) ...[
            const SizedBox(width: 8),
            Opacity(
              opacity: set.done || working ? .3 : 1,
              child: GestureDetector(
                onTap: set.done || working ? null : () => _startTimed(ref),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: c.surface2, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: AppIcon('play', size: 14, color: c.acc),
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          AppCheck(value: set.done, onChanged: (_) => _toggle(ref)),
        ]),
      ),
    );
  }

  /// Clearing an optional field drops the key rather than storing null, so a set only carries
  /// what was actually logged — in the session, in history and in a backup.
  void _setField(WidgetRef ref, String field, double? v) =>
      ref.read(appStateProvider.notifier).update((st) {
        st.active!.entries[entryIndex].sets[setIndex].setField(field, v);
      });

  /// A timed set is held, not typed. The work timer records what was actually held — an early
  /// finish logs 0:38 of a 0:45 target — and then checks the set off through the normal path,
  /// so rest, supersets and the finish prompt all behave exactly as they do for a reps set.
  void _startTimed(WidgetRef ref) {
    final s = ref.read(appStateProvider);
    final entry = s.active!.entries[entryIndex];
    ref.read(uiProvider).startWork(
      entry.sets[setIndex].sec ?? 45,
      exdb.or(entry.id).n,
      soundOn: s.sound,
      (elapsed) {
        ref.read(appStateProvider.notifier).update((st) {
          st.active!.entries[entryIndex].sets[setIndex].sec = elapsed;
        });
        final after = ref.read(appStateProvider).active;
        if (after != null && !after.entries[entryIndex].sets[setIndex].done) _toggle(ref);
      },
    );
  }

  /// Checking a set off is where most of the session's behaviour lives: the rest timer, the
  /// working-weight prompt and the finish prompt all hang off this one action.
  void _toggle(WidgetRef ref) {
    final s = ref.read(appStateProvider);
    final a = s.active;
    if (a == null) return;

    final units = supersetUnits(a.entries);
    final unit = unitOf(units, entryIndex);
    final unitIdx = units.indexWhere((u) => u.contains(entryIndex));
    final isLastUnit = unitIdx >= units.length - 1;
    final entry = a.entries[entryIndex];
    final mode = modeOf(entry.cfg);

    var askTop = false;
    var exJustDone = false;
    var workoutDone = false;

    ref.read(appStateProvider.notifier).update((st) {
      final e = st.active!.entries[entryIndex];
      final set = e.sets[setIndex];
      set.done = !set.done;
      if (!set.done) return;

      ref.read(uiProvider).setDone(st.sound);
      final isLastExInUnit = entryIndex == unit.last;
      final unitDone = unit.every((ui) =>
          st.active!.entries[ui].sets.every((x) => x.done));
      if (isLastExInUnit && !unitDone) {
        ref.read(uiProvider).startRest(st.restSec, soundOn: st.sound);
      } else if (unitDone) {
        ref.read(uiProvider).stopRest();
      }
      if (unitDone && isLastUnit) workoutDone = true;

      // Only loaded reps training has a "working weight" worth confirming — a bodyweight plank
      // has nothing to put in that slider, and neither does a set of push-ups.
      final loaded =
          mode == 'reps' && !(isBw(e.cfg) && !e.sets.any((x) => (x.w ?? 0) > 0));
      if (e.sets.every((x) => x.done)) {
        exJustDone = true;
        if (loaded && !e.asked) {
          e.asked = true;
          askTop = true;
        }
      }
    });

    // reps: the top-weight sheet first — it chains into the finish prompt on the last unit.
    // cardio/timed, or already confirmed: straight to the prompt.
    if (askTop) {
      topWeightSheet(ref, entryIndex);
    } else if (workoutDone) {
      workoutCompleteSheet(ref);
    } else if (exJustDone && mode == 'cardio') {
      ref.read(uiProvider).toast(t('Cardio logged'));
    } else if (exJustDone && mode == 'time') {
      ref.read(uiProvider).toast(t('Hold logged'));
    }
  }
}
