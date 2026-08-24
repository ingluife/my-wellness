import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';
import '../../theme/tokens.dart';

/// The weight slider.
///
/// Pointer-driven so the fill, track and thumb are all ours — a platform slider paints its own
/// track that no theme reaches and cannot pick up the accent colour. Dragging is absolute: the
/// thumb goes where your finger is, because this is used to dial in a body weight while
/// standing on a scale, not to nudge a value.
class AppSlider extends StatefulWidget {
  const AppSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.step = 1,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min, max, step;

  @override
  State<AppSlider> createState() => _AppSliderState();
}

class _AppSliderState extends State<AppSlider> {
  bool _dragging = false;

  double _valueAt(double dx, double width) {
    final f = (dx / width).clamp(0.0, 1.0);
    final raw = widget.min + f * (widget.max - widget.min);
    final snapped = (raw / widget.step).round() * widget.step;
    // step can be fractional (0.1) — round away the binary noise it leaves behind.
    return ((snapped * 1000).round() / 1000).clamp(widget.min, widget.max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final pct =
        ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0.0, 1.0);

    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      void report(Offset local) => widget.onChanged(_valueAt(local.dx, w));

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) {
          setState(() => _dragging = true);
          report(d.localPosition);
        },
        onHorizontalDragUpdate: (d) => report(d.localPosition),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        onTapDown: (d) => report(d.localPosition),
        child: SizedBox(
          height: 32,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 6,
                decoration:
                    BoxDecoration(color: c.surface3, borderRadius: BorderRadius.circular(99)),
                clipBehavior: Clip.antiAlias,
                child: FractionallySizedBox(
                  widthFactor: pct,
                  child:
                      DecoratedBox(decoration: BoxDecoration(color: c.acc, borderRadius: BorderRadius.circular(99))),
                ),
              ),
              Positioned(
                left: (w - 26) * pct,
                child: AnimatedScale(
                  duration: Motion.fast,
                  curve: Motion.ease,
                  scale: _dragging ? 1.14 : 1,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFFFFFF),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Color(0x38000000), blurRadius: 10, offset: Offset(0, 4)),
                        BoxShadow(color: Color(0x29000000), blurRadius: 2, offset: Offset(0, 1)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}
