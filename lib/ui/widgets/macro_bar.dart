import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/i18n.dart';
import '../../domain/nutrition.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// The day's calories as a ring, and its macros as three bars.
///
/// Hand-painted like every other chart here (line_chart, heatmap, body_map). There is no chart
/// package in this project and adding one for two shapes would be a poor trade.
///
/// Protein, carbohydrate and fat keep the same colour everywhere in the feature. They are read
/// dozens of times a week at a glance, and a legend you have to consult is a legend that has
/// already failed.
({Color p, Color c, Color f}) macroColors(BuildContext context) {
  final s = context.c.sys;
  return (p: s.blue, c: s.orange, f: s.yellow);
}

/// Calories against target.
///
/// Over the target is drawn in orange rather than red. Going over is ordinary — it happens most
/// weeks to most people, it is recoverable, and colouring it as a failure would make the screen
/// something to avoid opening, which is the one way a food log definitely stops working.
class KcalRing extends StatelessWidget {
  const KcalRing({
    super.key,
    required this.eaten,
    required this.target,
    this.size = 128,
    this.label,
  });

  final double eaten;
  final double target;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final over = target > 0 && eaten > target;
    final left = target - eaten;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: target > 0 ? eaten / target : 0,
          track: c.surface3,
          fill: over ? c.sys.orange : c.acc,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                left.abs().round().toString(),
                style: ts(TypeScale.large,
                    size: size * .26,
                    color: c.label,
                    weight: FontWeight.w600),
              ),
              Text(
                label ?? (over ? t('over') : t('left')),
                style: ts(TypeScale.cap, color: c.label3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.track, required this.fill});

  final double progress;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * .085;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, base);

    if (progress <= 0) return;
    // Past 100% the ring stops rather than lapping itself: a second lap reads as 20% eaten.
    final sweep = math.pi * 2 * progress.clamp(0.0, 1.0);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, base..color = fill);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.fill != fill || old.track != track;
}

/// Protein / carbs / fat against target, one bar each.
class MacroBars extends StatelessWidget {
  const MacroBars({super.key, required this.eaten, required this.target, this.compact = false});

  final Macros eaten;
  final Macros? target;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final m = macroColors(context);
    final tg = target;
    return Column(
      children: [
        _MacroBar(
            name: t('Protein'), got: eaten.p, goal: tg?.p, color: m.p, compact: compact),
        SizedBox(height: compact ? 6 : 9),
        _MacroBar(name: t('Carbs'), got: eaten.c, goal: tg?.c, color: m.c, compact: compact),
        SizedBox(height: compact ? 6 : 9),
        _MacroBar(name: t('Fat'), got: eaten.f, goal: tg?.f, color: m.f, compact: compact),
      ],
    );
  }
}

class _MacroBar extends StatelessWidget {
  const _MacroBar({
    required this.name,
    required this.got,
    required this.goal,
    required this.color,
    required this.compact,
  });

  final String name;
  final double got;
  final double? goal;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pct = (goal ?? 0) > 0 ? (got / goal!).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(name,
                  style: ts(TypeScale.foot, color: c.label2, weight: FontWeight.w500)),
            ),
            Text(
              goal == null
                  ? '${got.round()} g'
                  // "112 / 160 g" — the pair, because either number alone says nothing.
                  : '${got.round()} / ${goal!.round()} g',
              style: ts(TypeScale.foot, color: c.label3),
            ),
          ],
        ),
        SizedBox(height: compact ? 3 : 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: Stack(
            children: [
              Container(height: compact ? 5 : 7, color: c.surface3),
              FractionallySizedBox(
                widthFactor: pct,
                child: Container(height: compact ? 5 : 7, color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// One meal's or one food's macro split as a single stacked bar, by energy share.
///
/// By energy, not by grams: a gram of fat carries more than twice what a gram of carbohydrate
/// does, so a bar drawn from grams would show a spoon of oil as a sliver of a meal it dominates.
class MacroSplit extends StatelessWidget {
  const MacroSplit({super.key, required this.macros, this.height = 5});

  final Macros macros;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = macroColors(context);
    final p = macros.p * 4, cb = macros.c * 4, f = macros.f * 9;
    final total = p + cb + f;
    if (total <= 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: Container(height: height, color: c.surface3),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            Expanded(flex: math.max(0, (p / total * 1000).round()), child: ColoredBox(color: m.p)),
            Expanded(flex: math.max(0, (cb / total * 1000).round()), child: ColoredBox(color: m.c)),
            Expanded(flex: math.max(0, (f / total * 1000).round()), child: ColoredBox(color: m.f)),
          ],
        ),
      ),
    );
  }
}

/// The `P 112g · C 240g · F 62g` line that sits under a total.
class MacroLegend extends StatelessWidget {
  const MacroLegend({super.key, required this.macros, this.style});

  final Macros macros;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final m = macroColors(context);
    final base = style ?? ts(TypeScale.cap, color: c.label2);
    Widget dot(Color col, String label, double v) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text('$label ${v.round()}g', style: base),
          ],
        );
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        dot(m.p, t('P'), macros.p),
        dot(m.c, t('C'), macros.c),
        dot(m.f, t('F'), macros.f),
      ],
    );
  }
}
