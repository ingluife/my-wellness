import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_state.dart';
import '../../domain/format.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../state/app_state_provider.dart';
import 'package:go_router/go_router.dart';

import '../app.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_icon.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/pressable.dart';
import '../widgets/controls/slider.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/page.dart';
import 'sheet_service.dart';

/// The big weight readout, shared by the weigh-in and the goal.
///
/// A fixed range, not a moving window: a window that resizes itself mid-drag makes the thumb's
/// position unpredictable, because every time it grows everything already placed on it shifts
/// toward one side. A static range never has that problem, at the cost of coarser precision
/// per pixel — which is what the ±0.1 buttons and the nudge chips are for.
///
/// The ceiling follows the profile's unit: 300 covers a body weight or a working weight in kg,
/// but as pounds it cut off at 136 kg — below plenty of people's body weight.
class WeightInput extends StatelessWidget {
  const WeightInput({
    super.key,
    required this.value,
    required this.onChanged,
    required this.unit,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final String unit;

  static const lo = 1.0;
  static double hi(String unit) => unit == 'lb' ? 660 : 300;

  double _clamp(double x) => ((x * 10).round() / 10).clamp(lo, hi(unit)).toDouble();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Round(icon: 'minus', onTap: () => onChanged(_clamp(value - 0.1))),
              const SizedBox(width: 18),
              SizedBox(
                width: 158,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(fmtNum(value),
                        style: ts(TypeScale.large,
                            size: 52, color: c.label, weight: FontWeight.w600)),
                    const SizedBox(width: 4),
                    Text(unit, style: ts(TypeScale.body, size: 19, color: c.label2)),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              _Round(icon: 'plus', onTap: () => onChanged(_clamp(value + 0.1))),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final step in [-1.0, -0.5, 0.5, 1.0])
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3.5),
                  child: AppChip(
                    step < 0 ? '−${fmtNum(-step)}' : '+${fmtNum(step)}',
                    capitalize: false,
                    selected: false,
                    onTap: () => onChanged(_clamp(value + step)),
                  ),
                ),
            ],
          ),
        ),
        AppSlider(
          value: value.clamp(lo, hi(unit)).toDouble(),
          min: lo,
          max: hi(unit),
          step: 0.5,
          onChanged: (v) => onChanged(_clamp(v)),
        ),
      ],
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap});

  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable.builder(
      scale: .92,
      onTap: onTap,
      build: (context, pressed) => AnimatedContainer(
        duration: Motion.fast,
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: pressed ? c.surface2 : c.surface,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: AppIcon(icon, size: 19, color: c.label, stroke: 2.2),
      ),
    );
  }
}

/// Log today's body weight.
///
/// [required] is the check-in before a workout: it cannot be swiped away, because dismissing
/// it would skip a step rather than cancel one, and it offers the two honest ways out — start
/// without weighing in, or go and pick a different session.
Future<void> bwSheet({
  bool required = false,
  void Function(double? weight)? onDone,
}) =>
    showSheet<void>(
      locked: required,
      (context, close) => _BwSheet(required: required, onDone: onDone, close: close),
    );

class _BwSheet extends ConsumerStatefulWidget {
  const _BwSheet({required this.required, required this.onDone, required this.close});

  final bool required;
  final void Function(double? weight)? onDone;
  final void Function([void]) close;

  @override
  ConsumerState<_BwSheet> createState() => _BwSheetState();
}

class _BwSheetState extends ConsumerState<_BwSheet> {
  double? _v;

  void _save() {
    final n = ((_v ?? 0) * 10).round() / 10;
    if (n <= 0) {
      ref.read(uiProvider).toast(t('Enter a valid weight'));
      return;
    }
    ref.read(appStateProvider.notifier).update((s) {
      final iso = todayISO();
      final existing = s.bodyweight.where((b) => b.d == iso).firstOrNull;
      if (existing != null) {
        existing
          ..w = n
          ..t = DateTime.now().millisecondsSinceEpoch;
      } else {
        s.bodyweight.add(BodyWeightEntry(d: iso, w: n, t: DateTime.now().millisecondsSinceEpoch));
      }
      s.bodyweight.sort((a, b) => a.d.compareTo(b.d));
    });
    widget.close();
    if (widget.onDone != null) {
      widget.onDone!(n);
    } else {
      ref.read(uiProvider).toast(t('Weight saved'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final last = lastBW(s);
    final v = _v ??= last?.w ?? 70;
    final recent = s.bodyweight.reversed.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(widget.required ? t('Quick check-in') : t('Log body weight')),
        Text(
          widget.required
              ? t('Slide or tap to set your weight — tracked before every workout so your curve stays honest.')
              : '${t('Today')}, ${fmtDate(todayISO(), true)}',
          style: ts(TypeScale.foot, color: c.label2),
        ),
        WeightInput(value: v, unit: s.unit, onChanged: (x) => setState(() => _v = x)),
        const SizedBox(height: 14),
        AppButton(widget.required ? t('Save & start workout') : t('Save'),
            variant: BtnVariant.primary, onTap: _save),
        if (widget.required) ...[
          const SizedBox(height: 8),
          AppButton(t('Start without weighing in'),
              variant: BtnVariant.ghost,
              color: c.label3,
              onTap: () {
                widget.close();
                widget.onDone?.call(null);
              }),
          const SizedBox(height: 2),
          AppButton(t('Choose a different workout'),
              variant: BtnVariant.ghost,
              color: c.label3,
              icon: 'reset',
              onTap: () {
                widget.close();
                appNavigatorKey.currentContext?.go('/workout');
              }),
        ],
        if (!widget.required && recent.isNotEmpty) ...[
          SecHeading(t('Recent weigh-ins')),
          for (final b in recent)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 9),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.sep, width: R.hair)),
              ),
              child: Row(
                children: [
                  Expanded(
                      child: Text(fmtDate(b.d, true),
                          style: ts(TypeScale.foot, color: c.label2))),
                  Text('${fmtNum(b.w)} ${s.unit}',
                      style: ts(TypeScale.foot, color: c.label, weight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  IconButtonRound('trash',
                      size: 30,
                      iconSize: 15,
                      radius: 8,
                      color: c.sys.red,
                      onTap: () => ref
                          .read(appStateProvider.notifier)
                          .update((st) => st.bodyweight.removeWhere((x) => x.d == b.d))),
                ],
              ),
            ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Set or clear the target weight.
Future<void> goalSheet() => showSheet<void>((context, close) => _GoalSheet(close: close));

class _GoalSheet extends ConsumerStatefulWidget {
  const _GoalSheet({required this.close});

  final void Function([void]) close;

  @override
  ConsumerState<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends ConsumerState<_GoalSheet> {
  double? _v;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = ref.watch(appStateProvider);
    final v = _v ??= s.targetW ?? lastBW(s)?.w ?? 70;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetTitle(t('Target weight')),
        Text(
          t('Your goal is drawn as a line through the weight charts, and gains/losses are colored by whether they move toward it.'),
          style: ts(TypeScale.foot, color: c.label2),
        ),
        WeightInput(value: v, unit: s.unit, onChanged: (x) => setState(() => _v = x)),
        const SizedBox(height: 14),
        AppButton(t('Save goal'), variant: BtnVariant.primary, onTap: () {
          final n = (v * 10).round() / 10;
          if (n <= 0) {
            ref.read(uiProvider).toast(t('Enter a valid weight'));
            return;
          }
          ref.read(appStateProvider.notifier).update((st) => st.targetW = n);
          widget.close();
          final b = lastBW(ref.read(appStateProvider));
          final togo = b == null
              ? ''
              : ' (${t('{0} to go', fmtNum((n - b.w).abs()))})';
          ref.read(uiProvider).toast('${t('Goal set: {0}', '${fmtNum(n)} ${s.unit}')}$togo');
        }),
        if (s.targetW != null) ...[
          const SizedBox(height: 8),
          AppButton(t('Remove goal'), variant: BtnVariant.danger, onTap: () {
            ref.read(appStateProvider.notifier).update((st) => st.targetW = null);
            widget.close();
            ref.read(uiProvider).toast(t('Goal removed'));
          }),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// The colour a body-weight change is drawn in.
///
/// Without a goal a change is just a change — neutral. With one, moving toward it is the accent
/// and away from it is red, so the number carries its own verdict.
Color bwDeltaColor(BuildContext context, double delta, double currentW, double? targetW) {
  final c = context.c;
  if (delta == 0) return c.label2;
  if (targetW == null) return c.label;
  final up = targetW > currentW;
  return (delta > 0) == up ? c.acc : c.sys.red;
}
