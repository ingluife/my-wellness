import 'package:flutter/material.dart';

import '../../data/models/app_state.dart';
import '../../domain/format.dart';
import '../../domain/i18n.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// A year of training, one square per day.
///
/// Shaded by *time trained* rather than by volume or set count: an hour is an hour whether it
/// was heavy singles or a long easy session, and it is the only measure that compares across
/// the kinds of training the app supports. The four steps are quartiles of this profile's own
/// sessions, so the map reads against your own history rather than against an absolute.
class Heatmap extends StatefulWidget {
  const Heatmap({super.key, required this.state, this.onDay});

  final AppState state;
  final void Function(String iso)? onDay;

  @override
  State<Heatmap> createState() => _HeatmapState();
}

class _HeatmapState extends State<Heatmap> {
  final _scroll = ScrollController();

  static const _cell = 11.0;
  static const _gap = 3.0;
  static const _weeks = 53;

  @override
  void initState() {
    super.initState();
    // Opens on the present, which is the end of the strip.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final agg = <String, ({int n, double vol, int min})>{};
    for (final w in widget.state.workouts) {
      final cur = agg[w.d] ?? (n: 0, vol: 0.0, min: 0);
      agg[w.d] = (
        n: cur.n + 1,
        vol: cur.vol + (w.vol ?? 0),
        min: cur.min + (((w.end == 0 ? w.start : w.end) - w.start) / 60000).round().clamp(0, 1 << 30),
      );
    }

    final mins = [for (final a in agg.values) if (a.min > 0) a.min]..sort();
    double q(double p) => mins.isEmpty ? 0 : mins[(p * mins.length).floor().clamp(0, mins.length - 1)].toDouble();
    final t1 = q(.25), t2 = q(.5), t3 = q(.75);

    int level(({int n, double vol, int min})? a) {
      if (a == null) return 0;
      if (a.min == 0) return 1;
      if (a.min >= t3) return 4;
      if (a.min >= t2) return 3;
      if (a.min >= t1) return 2;
      return 1;
    }

    Color fill(int l) => switch (l) {
          1 => mix(c.acc, .30, c.surface2),
          2 => mix(c.acc, .55, c.surface2),
          3 => mix(c.acc, .78, c.surface2),
          4 => c.acc,
          _ => c.surface2,
        };

    final today = DateTime.now();
    final noonToday = DateTime(today.year, today.month, today.day, 12);
    // The strip ends on the Monday of this week, so the last column is the current week.
    final end = DateTime(
        noonToday.year, noonToday.month, noonToday.day - ((jsDay(noonToday) + 6) % 7), 12);
    final start = DateTime(end.year, end.month, end.day - (_weeks - 1) * 7, 12);

    final columns = <Widget>[];
    final monthLabels = <Widget>[];
    var lastMonth = -1;

    for (var wk = 0; wk < _weeks; wk++) {
      final colStart = DateTime(start.year, start.month, start.day + wk * 7, 12);
      // A month gets its label on the first column that starts inside it.
      final showMonth = colStart.month - 1 != lastMonth && colStart.day <= 7 && wk < _weeks - 2;
      monthLabels.add(SizedBox(
        width: _cell + _gap,
        child: showMonth
            ? Text(t(months[colStart.month - 1]),
                maxLines: 1, softWrap: false, style: ts(TypeScale.cap, size: 11, color: c.label3))
            : const SizedBox.shrink(),
      ));
      if (colStart.day <= 7) lastMonth = colStart.month - 1;

      final cells = <Widget>[];
      for (var d = 0; d < 7; d++) {
        final day = DateTime(colStart.year, colStart.month, colStart.day + d, 12);
        final key = isoOf(day);
        final a = agg[key];
        final future = day.isAfter(noonToday);
        cells.add(Padding(
          padding: EdgeInsets.only(top: d == 0 ? 0 : _gap),
          child: GestureDetector(
            onTap: a != null && widget.onDay != null ? () => widget.onDay!(key) : null,
            child: Opacity(
              opacity: future ? .3 : 1,
              child: Container(
                width: _cell,
                height: _cell,
                decoration: BoxDecoration(
                  color: fill(level(a)),
                  borderRadius: BorderRadius.circular(3),
                  border: key == todayISO() ? Border.all(color: c.acc, width: 1.5) : null,
                ),
              ),
            ),
          ),
        ));
      }
      columns.add(Padding(
        padding: EdgeInsets.only(left: wk == 0 ? 0 : _gap),
        child: Column(mainAxisSize: MainAxisSize.min, children: cells),
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 30, bottom: 5),
                child: Row(children: monthLabels),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 28,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final label in [t('Mon'), '', t('Wed'), '', t('Fri'), '', ''])
                          SizedBox(
                            height: _cell + _gap,
                            child: Text(label,
                                style: ts(TypeScale.cap, size: 10, color: c.label2)),
                          ),
                      ],
                    ),
                  ),
                  Row(children: columns),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 9),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(t('Less time'), style: ts(TypeScale.cap, size: 11, color: c.label3)),
              for (var i = 0; i <= 4; i++) ...[
                const SizedBox(width: 4),
                Container(
                  width: 10,
                  height: 10,
                  decoration:
                      BoxDecoration(color: fill(i), borderRadius: BorderRadius.circular(3)),
                ),
              ],
              const SizedBox(width: 4),
              Text(t('More time'), style: ts(TypeScale.cap, size: 11, color: c.label3)),
            ],
          ),
        ),
      ],
    );
  }
}
