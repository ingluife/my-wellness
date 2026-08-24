import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_drawing/path_drawing.dart';

import '../../domain/i18n.dart';
import '../../domain/muscles.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Front and back views of a body, each muscle shaded by how hard it was worked.
///
/// The five shade steps are the same ones the activity heatmap uses, so "more accent = more
/// training" means one thing everywhere in the app rather than two. Shading is *relative* to
/// the hardest-worked muscle in the same window — the map answers "is my training balanced",
/// which only means anything as a comparison within one period.
///
/// The geometry is ~90 KB of path data and only some screens show a map, so it is parsed on
/// first use and cached for the life of the app. Until it lands the widget holds its height,
/// so nothing below it jumps on arrival.
class BodyMap extends StatefulWidget {
  const BodyMap({
    super.key,
    required this.load,
    this.body = 'male',
    this.onMuscle,
    this.selected,
  });

  /// Effective sets per muscle — see `loadOf` in domain/muscles.dart.
  final Map<String, double> load;

  /// 'male' | 'female' — purely how the figure is drawn.
  final String body;

  /// Makes the map tappable. A muscle reports itself; tapping the same one again clears.
  final void Function(String slug)? onMuscle;

  final String? selected;

  @override
  State<BodyMap> createState() => _BodyMapState();
}

class _BodyMapState extends State<BodyMap> {
  static Map<String, _Figure>? _cache;
  static Future<Map<String, _Figure>>? _pending;

  Map<String, _Figure>? _figures;

  @override
  void initState() {
    super.initState();
    if (_cache != null) {
      _figures = _cache;
    } else {
      (_pending ??= _load()).then((f) {
        if (mounted) setState(() => _figures = f);
      });
    }
  }

  static Future<Map<String, _Figure>> _load() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/data/body_paths.json')) as Map;
    final out = <String, _Figure>{};
    raw.forEach((body, views) {
      final v = views as Map;
      out[body as String] = _Figure(
        front: _View.parse(Map<String, dynamic>.from(v['front'] as Map)),
        back: _View.parse(Map<String, dynamic>.from(v['back'] as Map)),
      );
    });
    return _cache = out;
  }

  @override
  Widget build(BuildContext context) {
    final f = _figures?[widget.body] ?? _figures?['male'];
    if (f == null) {
      // Holds the space while the geometry loads.
      return const SizedBox(height: 200);
    }
    final levels = levelsOf(widget.load);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: (MediaQuery.sizeOf(context).height * .46).clamp(0, 340),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _ViewPainter(view: f.front, levels: levels, host: widget)),
          const SizedBox(width: 6),
          Expanded(child: _ViewPainter(view: f.back, levels: levels, host: widget)),
        ],
      ),
    );
  }
}

class _Figure {
  const _Figure({required this.front, required this.back});

  final _View front;
  final _View back;
}

class _View {
  const _View({required this.viewBox, required this.parts});

  final Rect viewBox;

  /// Body-part slug -> its paths, already parsed.
  final Map<String, List<ui.Path>> parts;

  static _View parse(Map<String, dynamic> json) {
    final vb = (json['vb'] as String).split(RegExp(r'[ ,]+')).map(double.parse).toList();
    final parts = <String, List<ui.Path>>{};
    (json['p'] as Map).forEach((slug, list) {
      parts[slug as String] = [
        for (final d in list as List) parseSvgPathData(d as String),
      ];
    });
    return _View(
      viewBox: Rect.fromLTWH(vb[0], vb[1], vb[2], vb[3]),
      parts: parts,
    );
  }
}

class _ViewPainter extends StatelessWidget {
  const _ViewPainter({required this.view, required this.levels, required this.host});

  final _View view;
  final Map<String, int> levels;
  final BodyMap host;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    // An untrained muscle is derived from the text colour rather than a fixed surface, so the
    // body keeps the same contrast in both themes — pinned to `--surface-2` it was all but
    // invisible on a white card.
    final base = mix(c.label, .11, c.surface);
    final painter = _BodyPainter(
      view: view,
      levels: levels,
      selected: host.selected,
      base: base,
      accent: c.acc,
      silhouette: mix(c.label, .18, c.surface),
      separator: c.surface,
      outline: c.label,
    );

    Widget child = AspectRatio(
      aspectRatio: view.viewBox.width / view.viewBox.height,
      child: CustomPaint(painter: painter, size: Size.infinite),
    );

    if (host.onMuscle != null) {
      child = GestureDetector(
        onTapDown: (d) {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null) return;
          final hit = painter.muscleAt(d.localPosition, box.size);
          if (hit != null) host.onMuscle!(hit);
        },
        child: child,
      );
    }
    return child;
  }
}

class _BodyPainter extends CustomPainter {
  _BodyPainter({
    required this.view,
    required this.levels,
    required this.selected,
    required this.base,
    required this.accent,
    required this.silhouette,
    required this.separator,
    required this.outline,
  });

  final _View view;
  final Map<String, int> levels;
  final String? selected;
  final Color base, accent, silhouette, separator, outline;

  /// The same ramp the activity heatmap uses: nothing, then four steps toward the accent.
  Color _fill(int level) => switch (level) {
        1 => mix(accent, .32, base),
        2 => mix(accent, .56, base),
        3 => mix(accent, .78, base),
        4 => accent,
        _ => base,
      };

  Matrix4 _transform(Size size) {
    final k = size.width / view.viewBox.width;
    return Matrix4.identity()
      ..scaleByDouble(k, k, 1, 1)
      ..translateByDouble(-view.viewBox.left, -view.viewBox.top, 0, 1);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.transform(_transform(size).storage);

    // The artwork has no outline path of its own, so a hairline in the surface colour is what
    // separates neighbouring muscles — without it the body reads as one flat blob.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..color = separator
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;

    void drawAll(String slug, Color color) {
      for (final p in view.parts[slug] ?? const <ui.Path>[]) {
        canvas.drawPath(p, Paint()..color = color..isAntiAlias = true);
        canvas.drawPath(p, stroke);
      }
    }

    for (final slug in inert) {
      drawAll(slug, silhouette);
    }
    for (final slug in muscles) {
      drawAll(slug, _fill(levels[slug] ?? 0));
    }

    if (selected != null) {
      final sel = Paint()
        ..style = PaintingStyle.stroke
        ..color = outline
        ..strokeWidth = 7
        ..strokeJoin = StrokeJoin.round;
      for (final p in view.parts[selected!] ?? const <ui.Path>[]) {
        canvas.drawPath(p, sel);
      }
    }
    canvas.restore();
  }

  /// Which muscle is under a tap. Reverse order, so the muscle drawn last — the one actually
  /// visible where the paths overlap — is the one that answers.
  String? muscleAt(Offset local, Size size) {
    final inverse = Matrix4.tryInvert(_transform(size));
    if (inverse == null) return null;
    final p = MatrixUtils.transformPoint(inverse, local);
    for (final slug in muscles.reversed) {
      for (final path in view.parts[slug] ?? const <ui.Path>[]) {
        if (path.contains(p)) return slug;
      }
    }
    return null;
  }

  @override
  bool shouldRepaint(_BodyPainter old) =>
      old.selected != selected ||
      old.accent != accent ||
      old.base != base ||
      !mapEquals(old.levels, levels);
}

/// The shade key. Shares the heatmap's markup, because it is the same ramp.
class BodyMapLegend extends StatelessWidget {
  const BodyMapLegend({super.key, this.less, this.more});

  final String? less;
  final String? more;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    Color step(int i) => switch (i) {
          1 => mix(c.acc, .30, c.surface2),
          2 => mix(c.acc, .55, c.surface2),
          3 => mix(c.acc, .78, c.surface2),
          4 => c.acc,
          _ => c.surface2,
        };
    return Padding(
      padding: const EdgeInsets.only(top: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(less ?? t('Less'), style: ts(TypeScale.cap, size: 11, color: c.label3)),
          for (var i = 0; i <= 4; i++) ...[
            const SizedBox(width: 4),
            Container(
              width: 10,
              height: 10,
              decoration:
                  BoxDecoration(color: step(i), borderRadius: BorderRadius.circular(3)),
            ),
          ],
          const SizedBox(width: 4),
          Text(more ?? t('More'), style: ts(TypeScale.cap, size: 11, color: c.label3)),
        ],
      ),
    );
  }
}
