import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_state.dart';
import '../../domain/exercises.dart';
import '../../domain/format.dart';
import '../../domain/glyphs.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../domain/progression.dart';
import '../../state/app_state_provider.dart';
import '../app.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/select_row.dart';
import '../widgets/controls/stepper.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/controls/toggles.dart';
import '../widgets/media.dart';
import '../widgets/page.dart';
import 'exercise_sheets.dart';
import 'sheet_service.dart';

/// Put an exercise into a routine — pick which one, then configure it.
Future<void> addToRoutineSheet(Exercise ex) =>
    showSheet<void>((context, close) => _AddToRoutine(ex: ex, close: close));

class _AddToRoutine extends ConsumerWidget {
  const _AddToRoutine({required this.ex, required this.close});

  final Exercise ex;
  final void Function([void]) close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);

    void pick(String? routineId) {
      close();
      final isNew = routineId == null;
      exConfigSheet(
        ex: ex,
        routine: isNew ? null : s.routines.where((r) => r.id == routineId).firstOrNull,
        onSave: (cfg) {
          String? landedIn;
          ref.read(appStateProvider.notifier).update((st) {
            Routine? r;
            if (isNew) {
              r = Routine(id: uid(), name: t('New routine'), emoji: defaultGlyph);
              st.routines.add(r);
            } else {
              r = st.routines.where((x) => x.id == routineId).firstOrNull;
            }
            r?.ex.add(cfg.copy()..id = ex.id);
            landedIn = r?.id;
          });
          final r = ref.read(appStateProvider).routines.where((x) => x.id == landedIn).firstOrNull;
          ref.read(uiProvider).toast(t('“{0}” added to {1}', ex.n, r?.name ?? t('routine')));
          if (isNew && r != null) appNavigatorKey.currentContext?.go('/plan/r/${r.id}');
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t('Add “{0}”', capitalized(ex.n))),
        Text(t('Pick a routine — sets, reps & weight come next.'),
            style: ts(TypeScale.foot, color: c.label2)),
        const SizedBox(height: 12),
        AppList(children: [
          for (final r in s.routines)
            ListItem(
              leading: GlyphTile(glyphOf(r.emoji)),
              onTap: () => pick(r.id),
              trailing: [
                if (r.ex.any((e) => e.id == ex.id)) Tag(t('already in')),
                AppIcon('plus', size: 15, color: c.label, stroke: 2.4),
              ],
              child: ItemText(r.name, subtitle: exCount(r.ex.length)),
            ),
          ListItem(
            leading: GlyphTile('sparkles', background: c.surface3),
            onTap: () => pick(null),
            trailing: [AppIcon('plus', size: 15, color: c.label, stroke: 2.4)],
            child: ItemText(t('New routine'),
                subtitle: t('Create one and start with this exercise')),
          ),
        ]),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Configure one exercise: how many sets, of what, and how it should go up over time.
///
/// This is the sheet with the most rules in it, because it is where every mode and flag in the
/// app is actually chosen. It writes back only what differs from the dataset's own answer —
/// which is what keeps a plain barbell config byte-identical to what it was before bodyweight,
/// per-side and progression existed, and keeps a shared plan file small and readable.
Future<void> exConfigSheet({
  required Exercise ex,
  ExerciseConfig? existing,
  required void Function(ExerciseConfig cfg) onSave,
  VoidCallback? onDelete,
  Routine? routine,
}) =>
    showSheet<void>((context, close) => _ExConfig(
          ex: ex,
          existing: existing,
          onSave: onSave,
          onDelete: onDelete,
          routine: routine,
          close: close,
        ));

class _ExConfig extends ConsumerStatefulWidget {
  const _ExConfig({
    required this.ex,
    required this.existing,
    required this.onSave,
    required this.onDelete,
    required this.routine,
    required this.close,
  });

  final Exercise ex;
  final ExerciseConfig? existing;
  final void Function(ExerciseConfig cfg) onSave;
  final VoidCallback? onDelete;
  final Routine? routine;
  final void Function([void]) close;

  @override
  ConsumerState<_ExConfig> createState() => _ExConfigState();
}

class _ExConfigState extends ConsumerState<_ExConfig> {
  late ExerciseConfig c = (widget.existing?.copy() ?? defaultConfig(widget.ex.id))
    ..id = widget.ex.id;

  bool get _cardio => exdb.isCardio(widget.ex.id);
  String get _mode => _cardio ? 'cardio' : modeOf(c);
  bool get _bw => !_cardio && isBw(c);
  bool get _perSide => isPerSide(c);

  void _set(void Function(ExerciseConfig c) f) => setState(() => f(c));

  /// Keep whatever the other mode already had (sets, weight) and fill only what is missing.
  void _setMode(String m) => setState(() {
        final fresh = defaultConfig(widget.ex.id, m);
        c
          ..sets ??= fresh.sets
          ..reps ??= fresh.reps
          ..weight ??= fresh.weight
          ..sec ??= fresh.sec
          ..mode = m;
      });

  void _save() {
    widget.close();
    final sets = (c.sets ?? (_cardio ? 1 : 3)).round().clamp(1, 99).toDouble();

    if (_cardio) {
      widget.onSave(ExerciseConfig(
        sets: sets,
        min: (c.min ?? 20).round().clamp(1, 999).toDouble(),
        speed: (c.speed ?? 8).clamp(0, 99).toDouble(),
      ));
      return;
    }

    // Written only when it differs from what the dataset already says. `bodyweight` is true of
    // a hold as much as of a set of reps; `side` is not — it counts reps, and a timed hold has
    // none, so switching to Time drops it rather than carrying a flag nothing can read.
    final bwFlag = _bw != exdb.isBodyweightEq(widget.ex.id) ? _bw : null;
    // Only progression settings that differ from the inherited default are carried, so
    // "follow the routine" keeps meaning exactly that.
    final prog = c.prog;
    final inc = (c.inc ?? 0) > 0 ? c.inc : null;

    if (_mode == 'time') {
      widget.onSave(ExerciseConfig(
        sets: sets,
        mode: 'time',
        sec: (c.sec ?? 45).round().clamp(1, 3600).toDouble(),
        weight: (c.weight ?? 0).clamp(0, 999).toDouble(),
        bodyweight: bwFlag,
        prog: prog,
        inc: inc,
      ));
      return;
    }

    // A unilateral target is stored even: the split has to divide, and a typed 15 would
    // otherwise plan seven reps on one side and eight on the other, every session.
    final typed = (c.reps ?? 10).round().clamp(1, 999);
    final reps = _perSide ? (typed / 2).ceil() * 2 : typed;
    final out = ExerciseConfig(
      sets: sets,
      mode: 'reps',
      reps: reps.toDouble(),
      weight: (c.weight ?? 0).clamp(0, 999).toDouble(),
      bodyweight: bwFlag,
      side: _perSide ? true : null,
      prog: prog,
      inc: inc,
    );
    if (policyFor(c, widget.routine, 'reps') == 'double') {
      final min = (c.repsMin ?? (reps - 2).clamp(1, reps)).round().clamp(1, reps);
      out.repsMin = min.toDouble();
    }
    // A ceiling below the working reps would tell you to add a set on day one.
    if (_bw && !((c.weight ?? 0) > 0) && (c.repsMax ?? 0) > 0) {
      out.repsMax = c.repsMax!.round().clamp(reps, 999).toDouble();
    }
    widget.onSave(out);
  }

  @override
  Widget build(BuildContext context) {
    final col = context.c;
    final unit = ref.watch(appStateProvider.select((s) => s.unit));
    final timed = _mode == 'time';
    final added = _bw && (c.weight ?? 0) > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(capitalized(widget.ex.n)),
        ExerciseMedia(ex: widget.ex),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (_cardio) Tag(t('Cardio'), icon: 'figureRun', accent: true),
          Tag(t(widget.ex.tg.isNotEmpty ? widget.ex.tg : widget.ex.bp)),
          Tag(t(widget.ex.eq)),
        ]),
        const SizedBox(height: 14),
        if (!_cardio) ...[
          Segmented<String>(
            value: _mode,
            onChanged: _setMode,
            options: [SegOption('reps', label: t('Reps')), SegOption('time', label: t('Time'))],
          ),
          const SizedBox(height: 14),
        ],
        Row(children: [
          if (_cardio) ...[
            Expanded(
                child: AppStepper(
                    label: t('Intervals'),
                    value: c.sets,
                    step: 1,
                    decimal: false,
                    buttonWidth: 30,
                    onChanged: (v) => _set((x) => x.sets = v))),
            const SizedBox(width: 8),
            Expanded(
                child: AppStepper(
                    label: t('Minutes'),
                    value: c.min,
                    step: 1,
                    decimal: false,
                    buttonWidth: 30,
                    onChanged: (v) => _set((x) => x.min = v))),
            const SizedBox(width: 8),
            Expanded(
                child: AppStepper(
                    label: t('Speed (km/h)'),
                    value: c.speed,
                    step: 0.5,
                    buttonWidth: 30,
                    onChanged: (v) => _set((x) => x.speed = v))),
          ] else if (timed) ...[
            Expanded(
                child: AppStepper(
                    label: t('Sets'),
                    value: c.sets,
                    step: 1,
                    decimal: false,
                    buttonWidth: 30,
                    onChanged: (v) => _set((x) => x.sets = v))),
            const SizedBox(width: 8),
            Expanded(
                child: AppStepper(
                    label: t('Seconds'),
                    value: c.sec,
                    step: 5,
                    decimal: false,
                    buttonWidth: 30,
                    onChanged: (v) => _set((x) => x.sec = v))),
            const SizedBox(width: 8),
            Expanded(
                child: AppStepper(
                    label: t('Weight ({0})', unit),
                    value: c.weight,
                    step: 2.5,
                    buttonWidth: 30,
                    onChanged: (v) => _set((x) => x.weight = v))),
          ] else ...[
            Expanded(
                child: AppStepper(
                    label: t('Sets'),
                    value: c.sets,
                    step: 1,
                    decimal: false,
                    buttonWidth: 30,
                    onChanged: (v) => _set((x) => x.sets = v))),
            const SizedBox(width: 8),
            Expanded(
                child: AppStepper(
                    label: t('Reps'),
                    value: c.reps,
                    step: _perSide ? 2 : 1,
                    decimal: false,
                    buttonWidth: 30,
                    onChanged: (v) => _set((x) => x.reps = v))),
            // On bodyweight work the weight stepper is the extra tap the flag exists to
            // remove, so it is not here until there is a belt to describe.
            if (!_bw) ...[
              const SizedBox(width: 8),
              Expanded(
                  child: AppStepper(
                      label: t('Weight ({0})', unit),
                      value: c.weight,
                      step: 2.5,
                      buttonWidth: 30,
                      onChanged: (v) => _set((x) => x.weight = v))),
            ],
          ],
        ]),
        SizedBox(height: timed ? 8 : 18),
        if (timed && !_bw)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Text(
              t('A timer runs while you hold the set. Leave the weight at 0 for bodyweight holds.'),
              style: ts(TypeScale.foot, color: col.label3),
            ),
          ),
        if (!_cardio) ...[
          Section(children: [
            AppRow(
              icon: 'figureStrength',
              iconTint: col.acc,
              title: t('Bodyweight'),
              subtitle: _bw
                  ? t('No weight to enter — just log the reps.')
                  : t('Ask for a weight on every set.'),
              trailing: AppSwitch(
                value: _bw,
                onChanged: (v) => _set((x) {
                  x.bodyweight = v;
                  if (v) x.weight = 0;
                }),
              ),
            ),
            if (_mode == 'reps')
              AppRow(
                icon: 'shuffle',
                iconTint: col.sys.blue,
                title: t('Reps per side'),
                subtitle: _perSide
                    ? t('You still log the total: {0} is {1} per side.', fmtNum(c.reps ?? 0),
                        fmtNum(sideReps(c.reps)))
                    : t('For lunges, single-arm rows and the like.'),
                // Turning it on rounds the target up to an even number, since half of an odd
                // total is a rep one side does not get.
                trailing: AppSwitch(
                  value: _perSide,
                  onChanged: (v) => _set((x) {
                    x.side = v ? true : null;
                    if (v) x.reps = ((x.reps ?? 0) / 2).ceil() * 2;
                  }),
                ),
              ),
          ]),
        ],
        // A stepper is too wide to sit in a list row next to a label — it squeezes the text to
        // one word per line — so added weight gets the same full-width treatment as sets and
        // reps, with its explanation underneath.
        if (_bw) ...[
          AppStepper(
            label: t('Added ({0})', unit),
            value: c.weight ?? 0,
            step: 2.5,
            onChanged: (v) => _set((x) => x.weight = v),
          ),
          const SizedBox(height: 8),
          Text(t('For dips or pull-ups with a belt. Progression then follows the weight.'),
              style: ts(TypeScale.foot, color: col.label3)),
          const SizedBox(height: 18),
        ],
        // The rep ceiling only means something when there is no load to add instead.
        if (_mode == 'reps' && _bw && !added) ...[
          AppStepper(
            label: t('Top of the range'),
            value: c.repsMax ?? 0,
            step: 1,
            decimal: false,
            onChanged: (v) => _set((x) => x.repsMax = v),
          ),
          const SizedBox(height: 8),
          Text(
            (c.repsMax ?? 0) > 0
                ? t('Reps climb to {0}, then a set is added and the reps start over. At {1} sets it asks you to add weight instead.',
                    fmtNum(c.repsMax), maxBwSets)
                : t('Reps climb by one whenever every set was clean. Set a ceiling to add sets instead of reps forever.'),
            style: ts(TypeScale.foot, color: col.label3),
          ),
          const SizedBox(height: 18),
        ],
        ProgressionFields(
          ex: widget.ex,
          mode: _mode,
          cfg: c,
          routine: widget.routine,
          unit: unit,
          onChanged: (f) => _set(f),
        ),
        AppButton(widget.existing != null ? t('Save') : t('Add to routine'),
            variant: BtnVariant.primary, onTap: _save),
        if (widget.ex.custom) ...[
          const SizedBox(height: 8),
          AppButton(t('Edit or delete this exercise'),
              icon: 'pencil',
              onTap: () {
                widget.close();
                customExSheet(existing: widget.ex);
              }),
        ],
        if (widget.onDelete != null) ...[
          const SizedBox(height: 8),
          AppButton(t('Remove from routine'),
              variant: BtnVariant.danger,
              onTap: () {
                widget.close();
                widget.onDelete!();
              }),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Progression settings for one exercise.
///
/// Shown inside the config sheet because "how does this lift go up" belongs next to sets and
/// reps, not in a separate screen. Left on "follow the routine" it inherits, so most people
/// never touch it.
class ProgressionFields extends StatelessWidget {
  const ProgressionFields({
    super.key,
    required this.ex,
    required this.mode,
    required this.cfg,
    required this.routine,
    required this.unit,
    required this.onChanged,
  });

  final Exercise ex;
  final String mode;
  final ExerciseConfig cfg;
  final Routine? routine;
  final String unit;
  final void Function(void Function(ExerciseConfig c)) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final options = policiesFor[mode] ?? const ['off'];
    if (options.length < 2) return const SizedBox.shrink();

    final inherited = policyFor(ExerciseConfig(id: ex.id), routine, mode);
    final active = policyFor(cfg, routine, mode);
    final inc = (cfg.inc ?? 0) > 0
        ? cfg.inc!
        : (mode == 'time' ? defaultSecIncrement : defaultIncrement(ex.id, unit));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SecHeading(t('Progression'), margin: const EdgeInsets.fromLTRB(4, 0, 4, 8)),
        Section(children: [
          SelectRow<String>(
            title: t('Rule'),
            sheetTitle: t('Progression'),
            value: cfg.prog ?? '',
            onChanged: (v) => onChanged((x) => x.prog = v.isEmpty ? null : v),
            options: [
              SelectOption('', t('Follow the routine ({0})', t(policyName[inherited]!))),
              for (final p in options) SelectOption(p, t(policyName[p]!)),
            ],
          ),
        ]),
        Padding(
          padding: EdgeInsets.only(bottom: active == 'off' ? 18 : 10),
          child: Text(t(policyDesc[active]!), style: ts(TypeScale.foot, color: c.label3)),
        ),
        if (active != 'off') ...[
          Row(children: [
            Expanded(
              child: AppStepper(
                label: mode == 'time' ? t('Step (seconds)') : t('Step ({0})', unit),
                value: inc,
                step: mode == 'time' ? 5 : 1.25,
                decimal: mode != 'time',
                buttonWidth: 30,
                onChanged: (v) => onChanged((x) => x.inc = v),
              ),
            ),
            if (active == 'double') ...[
              const SizedBox(width: 8),
              Expanded(
                child: AppStepper(
                  label: t('Reps from'),
                  value: cfg.repsMin ?? ((cfg.reps ?? 10) - 2).clamp(1, 999),
                  step: 1,
                  decimal: false,
                  buttonWidth: 30,
                  onChanged: (v) => onChanged((x) => x.repsMin = v),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}
