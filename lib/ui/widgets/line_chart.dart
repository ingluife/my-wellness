import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/format.dart';
import '../../domain/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// One point on a curve.
class ChartPoint {
  const ChartPoint({required this.t, required this.y, this.d, this.mark, this.note});

  /// Milliseconds since epoch — the x position.
  final int t;

  final double y;

  /// The ISO day, when the point knows it. Used by the tooltip in preference to the timestamp.
  final String? d;

  /// A second reading carried by the same dot, 0..1 — bigger and more solid means more of it.
  ///
  /// Effort rides on the weight curve this way, because the two only mean something together:
  /// the same weight moved with less left in the tank is progress a weight-only chart draws
  /// as a flat line.
  final double? mark;

  /// Extra text for this point's tooltip.
  final String? note;
}

/// The app's one chart.
///
/// Hand-painted rather than taken from a charting package, because the original is hand-drawn
/// SVG and the geometry is part of the design: a 12% vertical breathing margin, nice-number
/// gridlines, month ticks that thin out rather than overlap, a gradient that fades to nothing,
/// and a goal line that reshapes the scale so the target is always on screen.
class LineChart extends StatefulWidget {
  const LineChart({
    super.key,
    required this.points,
    this.height = 150,
    this.unit = '',
    this.color,
    this.axes = true,
    this.goal,
    this.invert = false,
  });

  final List<ChartPoint> points;
  final double height;
  final String unit;
  final Color? color;
  final bool axes;

  /// Drawn as a dashed line, and folded into the y range so it is always visible.
  final double? goal;

  /// Flips the y axis, for a scale that counts down as it gets harder (RIR). Without it a
  /// curve of reps-in-reserve reads upside down, with the hardest sets at the floor.
  final bool invert;

  @override
  State<LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<LineChart> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    if (widget.points.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 44),
        child: Text(t('No data yet'),
            textAlign: TextAlign.center, style: ts(TypeScale.sub, color: c.label2)),
      );
    }

    final color = widget.color ?? c.acc;
    final geo = _Geometry(
      points: widget.points,
      height: widget.height,
      axes: widget.axes,
      goal: widget.goal,
      invert: widget.invert,
    );

    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      void hoverAt(Offset local) {
        final vx = local.dx / width * _Geometry.viewWidth;
        var best = 0;
        for (var i = 1; i < widget.points.length; i++) {
          if ((geo.x(widget.points[i].t) - vx).abs() <
              (geo.x(widget.points[best].t) - vx).abs()) {
            best = i;
          }
        }
        if (best != _hover) setState(() => _hover = best);
      }

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => hoverAt(d.localPosition),
        onHorizontalDragStart: (d) => hoverAt(d.localPosition),
        onHorizontalDragUpdate: (d) => hoverAt(d.localPosition),
        onHorizontalDragEnd: (_) => setState(() => _hover = null),
        onHorizontalDragCancel: () => setState(() => _hover = null),
        child: SizedBox(
          width: width,
          height: widget.height,
          child: Stack(
            children: [
              CustomPaint(
                size: Size(width, widget.height),
                painter: _LinePainter(
                  geo: geo,
                  color: color,
                  hover: _hover,
                  grid: c.sepOp,
                  axisLabel: c.label2,
                  goalColor: c.sys.yellow,
                  crosshair: c.label3,
                  ring: c.bg,
                ),
              ),
              if (_hover != null) _tooltip(context, geo, width),
            ],
          ),
        ),
      );
    });
  }

  /// Placed from the measured label rather than at a fixed offset: the chart lives in a clipped
  /// box, so a half-width offset hangs the label off the edge on the first and last point and
  /// the clip then eats it.
  Widget _tooltip(BuildContext context, _Geometry geo, double width) {
    final c = context.c;
    final p = widget.points[_hover!];
    final label = [
      fmtDate(p.d ?? isoOf(DateTime.fromMillisecondsSinceEpoch(p.t)), true),
      '${fmtNum(p.y)}${widget.unit.isEmpty ? '' : ' ${widget.unit}'}',
      if (p.note != null) p.note!,
    ].join(' · ');

    final cx = geo.x(p.t) / _Geometry.viewWidth * width;
    final cy = geo.y(p.y) / widget.height * widget.height;

    return CustomSingleChildLayout(
      delegate: _TooltipLayout(anchor: Offset(cx, cy)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), blurRadius: 18, spreadRadius: -4, offset: Offset(0, 6)),
          ],
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: ts(TypeScale.cap, color: c.label, weight: FontWeight.w500)),
      ),
    );
  }
}

/// Keeps the tooltip inside the chart, and drops it below the point when the point sits high
/// enough that the label would cover the very value it is reporting.
class _TooltipLayout extends SingleChildLayoutDelegate {
  const _TooltipLayout({required this.anchor});

  final Offset anchor;
  static const _margin = 4.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints.loose(Size(c.maxWidth - _margin * 2, c.maxHeight));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = (anchor.dx - child.width / 2).clamp(_margin, size.width - child.width - _margin);
    final y = anchor.dy < child.height + 14
        ? math.min(size.height - child.height - _margin, anchor.dy + 14)
        : _margin;
    return Offset(x, y.toDouble());
  }

  @override
  bool shouldRelayout(_TooltipLayout old) => old.anchor != anchor;
}

/// The chart's coordinate system, shared by the painter and the tooltip.
class _Geometry {
  _Geometry({
    required this.points,
    required this.height,
    required this.axes,
    required this.goal,
    required this.invert,
  }) {
    padLeft = axes ? 34 : 8;
    padBottom = axes ? 22 : 8;

    final ys = points.map((p) => p.y).toList();
    var lo = ys.reduce(math.min);
    var hi = ys.reduce(math.max);
    if (goal != null && goal!.isFinite) {
      lo = math.min(lo, goal!);
      hi = math.max(hi, goal!);
    }
    if (lo == hi) {
      lo -= 1;
      hi += 1;
    }
    // 12% breathing room, so a curve never runs along the frame.
    final pad = (hi - lo) * 0.12;
    yMin = lo - pad;
    yMax = hi + pad;

    t0 = points.first.t;
    t1 = points.last.t == t0 ? t0 + 1 : points.last.t;
  }

  static const viewWidth = 340.0;
  static const padRight = 12.0;
  static const padTop = 10.0;

  final List<ChartPoint> points;
  final double height;
  final bool axes;
  final double? goal;
  final bool invert;

  late final double padLeft;
  late final double padBottom;
  late final double yMin;
  late final double yMax;
  late final int t0;
  late final int t1;

  bool get single => points.length == 1;

  double x(int t) => t1 == t0
      ? (padLeft + viewWidth - padRight) / 2
      : padLeft + (t - t0) / (t1 - t0) * (viewWidth - padLeft - padRight);

  double y(double v) {
    final f = (v - yMin) / (yMax - yMin);
    return padTop + (invert ? f : 1 - f) * (height - padTop - padBottom);
  }

  /// Gridline values at a "nice" step — 1, 2, 2.5, 5 or 10 times a power of ten, so the labels
  /// read as round numbers rather than as whatever the data happened to span.
  List<double> gridValues() {
    final range = yMax - yMin;
    final raw = range / 3;
    final pow10 = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    var step = 10 * pow10;
    for (final m in [1, 2, 2.5, 5, 10]) {
      if (raw <= m * pow10) {
        step = m * pow10;
        break;
      }
    }
    final out = <double>[];
    for (var v = (yMin / step).ceil() * step; v <= yMax + 1e-9; v += step) {
      out.add(v);
    }
    return out;
  }

  /// One tick per month, or three spread across the range when the window is shorter than a
  /// month and there is no month boundary to hang a label on.
  List<({int t, String label, TextAlign align})> timeTicks() {
    final out = <({int t, String label, TextAlign align})>[];
    final d0 = DateTime.fromMillisecondsSinceEpoch(t0);
    final d1 = DateTime.fromMillisecondsSinceEpoch(t1);
    var m = DateTime(d0.year, d0.month + 1);
    while (!m.isAfter(d1)) {
      out.add((t: m.millisecondsSinceEpoch, label: t(months[m.month - 1]), align: TextAlign.center));
      m = DateTime(m.year, m.month + 1);
    }
    if (out.isEmpty && !single) {
      for (var i = 0; i <= 2; i++) {
        final tv = t0 + ((t1 - t0) * i / 2).round();
        final dd = DateTime.fromMillisecondsSinceEpoch(tv);
        out.add((
          t: tv,
          label: '${dd.day} ${t(months[dd.month - 1])}',
          align: i == 0 ? TextAlign.left : (i == 2 ? TextAlign.right : TextAlign.center),
        ));
      }
    }
    // Thin out rather than overlap.
    final every = math.max(1, (out.length / 7).ceil());
    return [
      for (var i = 0; i < out.length; i++)
        if (i % every == 0) out[i]
    ];
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter({
    required this.geo,
    required this.color,
    required this.hover,
    required this.grid,
    required this.axisLabel,
    required this.goalColor,
    required this.crosshair,
    required this.ring,
  });

  final _Geometry geo;
  final Color color, grid, axisLabel, goalColor, crosshair, ring;
  final int? hover;

  void _text(Canvas canvas, String s, Offset at, Color color, TextAlign align,
      {double size = 9.5, FontWeight weight = FontWeight.w400}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color, fontWeight: weight)),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    final dx = switch (align) {
      TextAlign.right => -tp.width,
      TextAlign.center => -tp.width / 2,
      _ => 0.0,
    };
    tp.paint(canvas, at + Offset(dx, -tp.height / 2));
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint, double on, double off) {
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final end = math.min(travelled + on, total);
      canvas.drawLine(a + dir * travelled, a + dir * end, paint);
      travelled = end + off;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _Geometry.viewWidth, 1);

    final right = _Geometry.viewWidth - _Geometry.padRight;
    final bottom = geo.height - geo.padBottom;

    if (geo.axes) {
      final gridPaint = Paint()
        ..color = grid
        ..strokeWidth = 1;
      for (final v in geo.gridValues()) {
        final y = geo.y(v);
        _dashed(canvas, Offset(geo.padLeft, y), Offset(right, y), gridPaint, 2, 4);
        _text(canvas, fmtNum(v), Offset(geo.padLeft - 5, y), axisLabel, TextAlign.right);
      }
      for (final tick in geo.timeTicks()) {
        final x = geo.x(tick.t);
        _dashed(canvas, Offset(x, _Geometry.padTop), Offset(x, bottom), gridPaint, 2, 4);
        _text(canvas, tick.label, Offset(x, geo.height - 7), axisLabel, tick.align);
      }
    }

    if (geo.goal != null && geo.goal!.isFinite) {
      final y = geo.y(geo.goal!);
      _dashed(canvas, Offset(geo.padLeft, y), Offset(right, y),
          Paint()..color = goalColor..strokeWidth = 1.6, 7, 4);
      _text(canvas, fmtNum(geo.goal), Offset(right - 2, y - 5), goalColor, TextAlign.right,
          weight: FontWeight.w700);
    }

    // A single point still draws a line, so the chart reads as a chart rather than as a dot.
    final pts = geo.single ? [geo.points.first, geo.points.first] : geo.points;
    final path = Path();
    for (var i = 0; i < pts.length; i++) {
      final o = Offset(geo.x(pts[i].t), geo.y(pts[i].y));
      i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
    }

    final fill = Path.from(path)
      ..lineTo(geo.x(pts.last.t), bottom)
      ..lineTo(geo.padLeft, bottom)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: .28), color.withValues(alpha: 0)],
        ).createShader(Rect.fromLTWH(0, 0, _Geometry.viewWidth, geo.height)),
    );

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = color
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true,
    );

    // The second reading, where a point carries one.
    for (final p in geo.points) {
      if (p.mark == null) continue;
      canvas.drawCircle(
        Offset(geo.x(p.t), geo.y(p.y)),
        2.4 + p.mark! * 3,
        Paint()..color = color.withValues(alpha: .3 + p.mark! * .7),
      );
    }

    canvas.drawCircle(
        Offset(geo.x(pts.last.t), geo.y(pts.last.y)), 4, Paint()..color = color);

    if (hover != null && hover! < geo.points.length) {
      final p = geo.points[hover!];
      final hx = geo.x(p.t);
      final hy = geo.y(p.y);
      final cross = Paint()
        ..color = crosshair
        ..strokeWidth = 1;
      _dashed(canvas, Offset(hx, _Geometry.padTop), Offset(hx, bottom), cross, 3, 3);
      _dashed(canvas, Offset(geo.padLeft, hy), Offset(right, hy), cross, 3, 3);
      canvas.drawCircle(Offset(hx, hy), 5, Paint()..color = color);
      // A ring in the page colour, so the highlighted point stays legible wherever the curve
      // happens to cross it.
      canvas.drawCircle(
        Offset(hx, hy),
        5,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = ring
          ..strokeWidth = 2,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.hover != hover || old.color != color;
}
