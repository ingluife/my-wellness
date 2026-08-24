import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../app_icon.dart';
import 'fields.dart';
import 'pressable.dart';

/// A −/value/+ control, optionally with a label above it.
///
/// The same markup serves the exercise-config sheet and every set row in a workout, which is
/// why the sizes are parameters: a set row fits two of these next to a checkbox, and three
/// once effort is switched on, so the buttons narrow rather than the row wrapping.
class AppStepper extends StatelessWidget {
  const AppStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.step = 1,
    this.decimal = true,
    this.label,
    this.unit,
    this.buttonWidth = 40,
    this.buttonHeight = 44,
    this.fontSize,
    this.nullable = false,
    this.onStep,
  });

  final double? value;
  final ValueChanged<double?> onChanged;
  final double step;
  final bool decimal;
  final String? label;
  final String? unit;
  final double buttonWidth;
  final double buttonHeight;
  final double? fontSize;

  /// See [NumberField.nullable] — the effort column clears to null rather than to 0.
  final bool nullable;

  /// Overrides what one tap does. The effort column walks its own scale (and can step *off*
  /// it back to unlogged), which plain arithmetic on [step] cannot express.
  final double? Function(int dir)? onStep;

  void _bump(int dir) {
    if (onStep != null) {
      onChanged(onStep!(dir));
      return;
    }
    final next = ((value ?? 0) + dir * step) * 100;
    onChanged((next.round() / 100).clamp(0, double.infinity).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final inner = Container(
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          _StepButton(icon: 'minus', w: buttonWidth, h: buttonHeight, onTap: () => _bump(-1)),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: NumberField(
                    value: value,
                    onChanged: onChanged,
                    decimal: decimal,
                    nullable: nullable,
                    style: ts(TypeScale.body,
                        color: c.label, weight: FontWeight.w500, size: fontSize),
                  ),
                ),
                if (unit != null) ...[
                  const SizedBox(width: 3),
                  Text(unit!, style: ts(TypeScale.cap, color: c.label2)),
                ],
              ],
            ),
          ),
          _StepButton(icon: 'plus', w: buttonWidth, h: buttonHeight, onTap: () => _bump(1)),
        ],
      ),
    );

    if (label == null) return inner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label!,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: ts(TypeScale.foot, color: c.label2),
        ),
        const SizedBox(height: 6),
        inner,
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.w, required this.h, required this.onTap});

  final String icon;
  final double w, h;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Pressable.builder(
      scale: 1,
      onTap: onTap,
      build: (context, pressed) => AnimatedContainer(
        duration: Motion.fast,
        width: w,
        height: h,
        color: pressed ? c.surface3 : null,
        alignment: Alignment.center,
        child: AppIcon(icon, size: 16, color: c.label, stroke: 2.2),
      ),
    );
  }
}
