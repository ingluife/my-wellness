import 'package:flutter/widgets.dart';
import 'package:path_drawing/path_drawing.dart';
import '../theme/tokens.dart';

part 'icon_paths.dart';

/// One shape of an icon, in the 24x24 source coordinate space.
///
/// Circles and rects are kept as themselves rather than flattened into path data: the source
/// draws them with `<circle>` and `<rect rx>`, and converting those to arc commands is a
/// chance to be subtly wrong about a radius for no gain.
sealed class IconShape {
  const IconShape({this.filled = false});

  /// Solid rather than stroked — `fill="currentColor" stroke="none"` in the source.
  final bool filled;
}

final class IconPath extends IconShape {
  const IconPath(this.d, {super.filled});
  final String d;
}

final class IconCircle extends IconShape {
  const IconCircle(this.cx, this.cy, this.r, {super.filled});
  final double cx, cy, r;
}

final class IconRect extends IconShape {
  const IconRect(this.x, this.y, this.w, this.h, this.rx);
  final double x, y, w, h, rx;
}

/// Every icon key, including the aliases. Used by `glyphOf()` to tell an icon key apart from
/// a legacy emoji stored in `routine.emoji`.
final iconNames = _icons.keys.toList(growable: false);

/// Parsed paths are cached per key: the geometry never changes, and re-parsing ~10 path
/// strings on every rebuild of a tab bar or a list row is pure waste.
final _cache = <String, List<(Path, bool)>>{};

List<(Path, bool)> _shapesFor(String name) => _cache.putIfAbsent(name, () {
      final out = <(Path, bool)>[];
      for (final s in _icons[name]!) {
        final p = switch (s) {
          IconPath(:final d) => parseSvgPathData(d),
          IconCircle(:final cx, :final cy, :final r) => Path()
            ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
          IconRect(:final x, :final y, :final w, :final h, :final rx) => Path()
            ..addRRect(RRect.fromRectAndRadius(
                Rect.fromLTWH(x, y, w, h), Radius.circular(rx))),
        };
        out.add((p, s.filled));
      }
      return out;
    });

/// Overrides the stroke weight for the icons beneath it.
///
/// The CSS carries this as `--icon-stroke`, set on the *container* — a chevron in a list row
/// is drawn at 2.4 and the same chevron in a tab bar at 1.65, without either call site
/// knowing which icon it is styling. An inherited widget is the same mechanism.
class IconStroke extends InheritedWidget {
  const IconStroke({super.key, required this.width, required super.child});

  final double width;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<IconStroke>()?.width ?? R.iconStroke;

  @override
  bool updateShouldNotify(IconStroke old) => old.width != width;
}

/// `AppIcon('flame')` — inherits colour and size from its context, like `1em` + `currentColor`.
///
/// [size] defaults to the surrounding [DefaultTextStyle]'s font size, which is how the source
/// gets an icon to match the text it sits next to without being told a pixel value.
class AppIcon extends StatelessWidget {
  const AppIcon(this.name, {super.key, this.size, this.color, this.stroke});

  final String name;
  final double? size;
  final Color? color;
  final double? stroke;

  @override
  Widget build(BuildContext context) {
    if (!_icons.containsKey(name)) return const SizedBox.shrink();
    final ds = DefaultTextStyle.of(context).style;
    final s = size ?? ds.fontSize ?? 17;
    return SizedBox(
      width: s,
      height: s,
      child: CustomPaint(
        painter: _IconPainter(
          shapes: _shapesFor(name),
          color: color ?? ds.color ?? const Color(0xFF000000),
          stroke: stroke ?? IconStroke.of(context),
        ),
      ),
    );
  }
}

class _IconPainter extends CustomPainter {
  _IconPainter({required this.shapes, required this.color, required this.stroke});

  final List<(Path, bool)> shapes;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.save();
    canvas.scale(k);
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      // The stroke is specified in the 24x24 space, so it scales with the icon — which is
      // what makes one weight read as one weight at 10px and at 54px.
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final fillPaint = Paint()..color = color..isAntiAlias = true;
    for (final (path, filled) in shapes) {
      canvas.drawPath(path, filled ? fillPaint : strokePaint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_IconPainter old) =>
      old.color != color || old.stroke != stroke || !identical(old.shapes, shapes);
}
