import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_state.dart';
import '../../domain/exercises.dart';
import '../../domain/format.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../domain/onerm.dart';
import '../../state/app_state_provider.dart';
import '../app.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/fields.dart';
import '../widgets/controls/stepper.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/media.dart';
import '../widgets/page.dart';
import 'routine_sheets.dart';
import 'sheet_service.dart';

/// Everything an exercise can be looked at through: its detail sheet, the picker that finds
/// one, and the little 1RM calculator that rides along on the detail.

/// The detail sheet — the animation, what it trains, your best, an estimate, and the how-to.
Future<void> exerciseDetailSheet(Exercise ex) => showSheet<void>(
      (context, close) => _ExerciseDetail(ex: ex, close: close),
    );

class _ExerciseDetail extends ConsumerWidget {
  const _ExerciseDetail({required this.ex, required this.close});

  final Exercise ex;
  final void Function([void]) close;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final last = lastEntryFor(s, ex.id);
    final best = bestWeightFor(s, ex.id);
    final steps = ex.steps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(capitalized(ex.n)),
        ExerciseMedia(ex: ex),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            Tag(t(ex.bp), accent: true),
            if (ex.tg.isNotEmpty) Tag(t(ex.tg), icon: 'target'),
            if (ex.eq.isNotEmpty) Tag(t(ex.eq), icon: 'dumbbell'),
            for (final m in ex.sm.take(3)) Tag(t(m)),
          ],
        ),
        const SizedBox(height: 10),
        if (ex.desc.isNotEmpty) _Note(ex.desc),
        if (best > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                AppIcon('trophy', size: 14, color: c.sys.yellow),
                const SizedBox(width: 5),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${t('Best:')} '),
                      TextSpan(
                        text: '${fmtNum(best)} ${s.unit}',
                        style: ts(TypeScale.foot, color: c.acc, weight: FontWeight.w600),
                      ),
                      if (last != null)
                        TextSpan(
                          text: ' · ${t('last')} ${fmtDate(last.d)}: '
                              '${last.sets.map((x) => setLabel(ex.id, x, last.target)).join(', ')}',
                        ),
                    ]),
                    style: ts(TypeScale.foot, color: c.label),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        AppButton(t('Add to my plan'),
            variant: BtnVariant.primary,
            icon: 'plus',
            onTap: () {
              close();
              addToRoutineSheet(ex);
            }),
        if (!exdb.isCardio(ex.id)) OneRepMaxCalculator(ex: ex),
        if (steps.isNotEmpty) ...[
          SecHeading(t('How to')),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 18,
                    child: Text('${i + 1}.', style: ts(TypeScale.sub, color: c.label3)),
                  ),
                  Expanded(child: Text(steps[i], style: ts(TypeScale.sub, color: c.label2))),
                ],
              ),
            ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: ts(TypeScale.sub, color: c.label2)),
    );
  }
}

/// Estimated 1RM for one exercise: what the log already implies, plus a calculator for a set
/// you have not done — so the number is reachable before there is any history.
class OneRepMaxCalculator extends ConsumerStatefulWidget {
  const OneRepMaxCalculator({super.key, required this.ex});

  final Exercise ex;

  @override
  ConsumerState<OneRepMaxCalculator> createState() => _OneRepMaxCalculatorState();
}

class _OneRepMaxCalculatorState extends ConsumerState<OneRepMaxCalculator> {
  double? _w;
  double? _r;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final best = best1RM(s, widget.ex.id);
    final w = _w ??= best?.w ?? s.exWeights[widget.ex.id]?.w ?? 20;
    final r = _r ??= best?.r.toDouble() ?? 5;
    final est = estimate1RM(w, r);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SecHeading(t('Estimated 1RM')),
        if (best != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${t('From your log:')} '),
                TextSpan(
                  text: '${fmtNum(best.est)} ${s.unit}',
                  style: ts(TypeScale.foot, color: c.acc, weight: FontWeight.w600),
                ),
                TextSpan(
                  text: ' · ${t('{0} × {1} on {2}', '${fmtNum(best.w)} ${s.unit}', best.r, fmtDate(best.d, true))}',
                  style: ts(TypeScale.foot, color: c.label3),
                ),
              ]),
              style: ts(TypeScale.foot, color: c.label),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: AppStepper(
                label: t('Weight ({0})', s.unit),
                value: w,
                step: 2.5,
                onChanged: (v) => setState(() => _w = v ?? 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AppStepper(
                label: t('Reps'),
                value: r,
                step: 1,
                decimal: false,
                onChanged: (v) => setState(() => _r = v ?? 0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(t('Estimate'), style: ts(TypeScale.foot, color: c.label2)),
            Text(
              est == null ? '—' : '${fmtNum(est)} ${s.unit}',
              style: ts(TypeScale.title2, size: 20, color: c.acc, weight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          est == null
              ? t('Enter a weight and 1–{0} reps — beyond that an estimate is guesswork.', repCap)
              : t('Epley formula — a calculation from one set, not a tested max.'),
          style: ts(TypeScale.foot, color: c.label3),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Exercises already used in your routines or past workouts — the "Chosen" filter, and the
/// marker that says you have picked this one before.
Map<String, int> _usageMap(AppState s) {
  final u = <String, int>{};
  for (final r in s.routines) {
    for (final e in r.ex) {
      if (e.id != null) u[e.id!] = (u[e.id!] ?? 0) + 1;
    }
  }
  for (final w in s.workouts) {
    for (final e in w.entries) {
      u[e.id] = (u[e.id] ?? 0) + 1;
    }
  }
  return u;
}

/// Pick an exercise. Opens on everything, narrows by search, body part and equipment, and
/// offers what you have already chosen first — which is what you want when building a routine
/// out of the twenty exercises you actually do.
///
/// Stays open under whatever picking an exercise leads to (the config sheet, the custom-exercise
/// form) so dismissing that leaves you back on the list exactly as you left it — same search,
/// same chips, same page, same scroll. Picking calls `onPick` but never pops itself; only the
/// shell's own close (the chevron, the drag, the barrier) does.
Future<void> exercisePicker(void Function(Exercise ex) onPick) =>
    showSheet<void>((context, close) => _ExercisePicker(onPick: onPick, close: close));

class _ExercisePicker extends ConsumerStatefulWidget {
  const _ExercisePicker({required this.onPick, required this.close});

  final void Function(Exercise ex) onPick;
  final void Function([void]) close;

  @override
  ConsumerState<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends ConsumerState<_ExercisePicker> {
  final _search = TextEditingController();
  String _q = '';

  /// '' = all, '*' = chosen, else a body part.
  String _bp = '';
  String _eq = '';
  int _shown = 50;

  static const _chosen = '*';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final usage = _usageMap(s);
    final ql = _q.toLowerCase().trim();
    final all = exdb.all(s);

    var base = all.where((e) {
      if (_bp == _chosen) {
        if (!usage.containsKey(e.id)) return false;
      } else if (_bp.isNotEmpty && e.bp != _bp) {
        return false;
      }
      if (ql.isEmpty) return true;
      return e.n.toLowerCase().contains(ql) ||
          e.tg.contains(ql) ||
          e.eq.contains(ql) ||
          e.desc.toLowerCase().contains(ql);
    }).toList();

    if (_bp == _chosen) {
      base.sort((a, b) {
        final d = (usage[b.id] ?? 0) - (usage[a.id] ?? 0);
        return d != 0 ? d : a.n.compareTo(b.n);
      });
    }

    final eqOpts = exdb.equipmentOf(base);
    final eqOn = eqOpts.contains(_eq) ? _eq : '';
    final f = eqOn.isEmpty ? base : base.where((e) => e.eq == eqOn).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t('Add exercise')),
        SearchField(
          controller: _search,
          value: _q,
          placeholder: t('Search {0} exercises…', all.length),
          onChanged: (v) => setState(() {
            _q = v;
            _shown = 50;
          }),
        ),
        const SizedBox(height: 10),
        ChipRow(children: [
          if (usage.isNotEmpty)
            AppChip(
              '${t('Chosen')} (${usage.length})',
              icon: 'starFill',
              capitalize: false,
              selected: _bp == _chosen,
              onTap: () => setState(() {
                _bp = _chosen;
                _eq = '';
                _shown = 50;
              }),
            ),
          AppChip(t('All'),
              capitalize: false,
              selected: _bp.isEmpty,
              onTap: () => setState(() {
                    _bp = '';
                    _eq = '';
                    _shown = 50;
                  })),
          for (final b in exdb.bodyParts)
            AppChip(t(b),
                selected: _bp == b,
                onTap: () => setState(() {
                      _bp = b;
                      _eq = '';
                      _shown = 50;
                    })),
        ]),
        if (eqOpts.length > 1) ...[
          const SizedBox(height: 8),
          ChipRow(children: [
            AppChip(t('Any equipment'),
                capitalize: false,
                selected: eqOn.isEmpty,
                onTap: () => setState(() {
                      _eq = '';
                      _shown = 50;
                    })),
            for (final x in eqOpts)
              AppChip(t(x),
                  selected: eqOn == x,
                  onTap: () => setState(() {
                        _eq = x;
                        _shown = 50;
                      })),
          ]),
        ],
        const SizedBox(height: 10),
        AppList(children: [
          if (_bp != _chosen)
            ListItem(
              leading: Container(
                width: 50,
                height: 50,
                decoration:
                    BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(9)),
                alignment: Alignment.center,
                child: AppIcon('sparkles', size: 21, color: c.label2),
              ),
              trailing: [AppIcon('plus', size: 15, color: c.label, stroke: 2.4)],
              onTap: () => customExSheet(prefill: _q.trim(), onDone: widget.onPick),
              child: ItemText(t('Create your own exercise'),
                  subtitle: t('name + body part, no animation')),
            ),
          for (final e in f.take(_shown))
            ListItem(
              leading: ExerciseThumb(ex: e),
              onTap: () => widget.onPick(e),
              trailing: [
                if (usage.containsKey(e.id))
                  Tag(null, icon: 'starFill', accent: true),
                AppIcon('plus', size: 15, color: c.label, stroke: 2.4),
              ],
              child: ItemText(e.n,
                  capitalize: true,
                  subtitle: '${t(e.tg.isNotEmpty ? e.tg : e.bp)} · ${t(e.eq)}'),
            ),
          if (f.isEmpty && _bp == _chosen)
            EmptyState(message: t('Nothing chosen yet — add exercises and they’ll show up here.')),
        ]),
        if (f.length > _shown) ...[
          const SizedBox(height: 8),
          AppButton(t('Show more'), onTap: () => setState(() => _shown += 50)),
        ],
      ],
    );
  }
}

/// Create or edit one of your own exercises.
///
/// A name and a body part is all it takes — it then behaves like any built-in one everywhere
/// (planning, logging, PRs, stats), just without an animation.
Future<void> customExSheet({
  Exercise? existing,
  String prefill = '',
  void Function(Exercise ex)? onDone,
}) =>
    showSheet<void>((context, close) =>
        _CustomExForm(existing: existing, prefill: prefill, onDone: onDone, close: close));

class _CustomExForm extends ConsumerStatefulWidget {
  const _CustomExForm({
    required this.existing,
    required this.prefill,
    required this.onDone,
    required this.close,
  });

  final Exercise? existing;
  final String prefill;
  final void Function(Exercise ex)? onDone;
  final void Function([void]) close;

  @override
  ConsumerState<_CustomExForm> createState() => _CustomExFormState();
}

class _CustomExFormState extends ConsumerState<_CustomExForm> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.n ?? widget.prefill);
  late final TextEditingController _desc =
      TextEditingController(text: widget.existing?.desc ?? '');
  late String _bp = widget.existing?.bp ?? '';

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _save() {
    final ui = ref.read(uiProvider);
    final name = _name.text.trim();
    if (name.isEmpty) return ui.toast(t('Give it a name'));
    if (_bp.isEmpty) return ui.toast(t('Pick a body part'));

    final s = ref.read(appStateProvider);
    final dup = exdb.all(s).where((e) =>
        e.n.toLowerCase() == name.toLowerCase() && e.id != widget.existing?.id);
    if (dup.isNotEmpty) return ui.toast(t('“{0}” already exists', dup.first.n));

    final desc = _desc.text.trim();
    final trimmed = desc.length > 1000 ? desc.substring(0, 1000) : desc;
    final existing = widget.existing;
    final id = existing?.id ?? 'c${uid()}';

    ref.read(appStateProvider.notifier).update((st) {
      if (existing != null) {
        for (final ce in st.customEx) {
          if (ce.id == id) {
            ce
              ..n = name
              ..bp = _bp
              ..desc = trimmed;
          }
        }
      } else {
        st.customEx.add(CustomExercise(id: id, n: name, bp: _bp, desc: trimmed));
      }
    });

    widget.close();
    ui.toast(existing != null ? t('Saved') : t('“{0}” created', name));
    final made = exdb[id];
    if (made != null) widget.onDone?.call(made);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final editing = widget.existing != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(editing ? t('Edit custom exercise') : t('Create your own exercise')),
        Text(
          t('Name it and pick a body part — it behaves like any other exercise, just without an animation.'),
          style: ts(TypeScale.foot, color: c.label2),
        ),
        const SizedBox(height: 12),
        AppTextField(controller: _name, placeholder: t('Exercise name'), maxLength: 60),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            for (final b in exdb.bodyParts)
              AppChip(t(b), selected: _bp == b, onTap: () => setState(() => _bp = b)),
          ],
        ),
        if (_bp == 'cardio')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              AppIcon('figureRun', size: 13, color: c.label3),
              const SizedBox(width: 5),
              Expanded(
                child: Text(t('Cardio exercises log time + speed instead of weight × reps.'),
                    style: ts(TypeScale.foot, color: c.label3)),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        AppTextField(
          controller: _desc,
          maxLines: 4,
          maxLength: 1000,
          placeholder: t('Description (optional) — setup, cues, anything you want to remember'),
        ),
        const SizedBox(height: 14),
        AppButton(editing ? t('Save') : t('Create exercise'),
            variant: BtnVariant.primary, onTap: _save),
        if (editing) ...[
          const SizedBox(height: 8),
          AppButton(t('Delete exercise'),
              variant: BtnVariant.danger,
              icon: 'trash',
              onTap: () {
                widget.close();
                deleteCustomEx(ref, widget.existing!);
              }),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Remove one of your own exercises.
///
/// Already-logged workouts keep their sets — the name is stamped into them on the way out, so
/// history stays readable rather than turning into a row of raw ids.
void deleteCustomEx(WidgetRef ref, Exercise ex, {VoidCallback? afterDelete}) {
  final s = ref.read(appStateProvider);
  if (s.active?.entries.any((e) => e.id == ex.id) ?? false) {
    ref.read(uiProvider).toast(t('Finish your current workout first'));
    return;
  }
  confirmSheet(
    title: t('Delete “{0}”?', ex.n),
    message: t('It will be removed from your routines. Already-logged workouts keep their sets.'),
    confirmText: t('Delete'),
    danger: true,
    onConfirm: () {
      ref.read(appStateProvider.notifier).update((st) {
        st.customEx.removeWhere((x) => x.id == ex.id);
        for (final r in st.routines) {
          r.ex.removeWhere((e) => e.id == ex.id);
          cleanupSg(r.ex);
        }
        for (final w in st.workouts) {
          for (final e in w.entries) {
            if (e.id == ex.id) e.n = ex.n;
          }
        }
        st.exWeights.remove(ex.id);
      });
      ref.read(uiProvider).toast(t('Exercise deleted'));
      afterDelete?.call();
    },
  );
}
