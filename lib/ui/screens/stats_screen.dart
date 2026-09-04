import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/app_state.dart';
import '../../domain/effort.dart';
import '../../domain/exercises.dart';
import '../../domain/format.dart';
import '../../domain/history.dart';
import '../../domain/i18n.dart';
import '../../domain/muscles.dart';
import '../../domain/nutrition.dart';
import '../../domain/onerm.dart';
import '../../state/app_state_provider.dart';
import '../sheets/calendar_sheet.dart';
import '../sheets/weight_sheets.dart';
import '../sheets/workout_flow.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/body_map.dart';
import '../widgets/controls/app_button.dart';
import '../widgets/controls/select_row.dart';
import '../widgets/controls/surfaces.dart';
import '../widgets/controls/toggles.dart';
import '../widgets/heatmap.dart';
import '../widgets/line_chart.dart';
import '../widgets/macro_bar.dart';
import '../widgets/page.dart';
import 'routine_edit_screen.dart' show MuscleChip;

/// Stats is the analytics hub: every chart, every trend, and the way into the full history.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  int _range = 90;
  String? _exId;
  String _exMetric = 'top';

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final now = DateTime.now().millisecondsSinceEpoch;

    final bw30 = s.bodyweight
        .where((b) => (b.t ?? dayOf(b.d).millisecondsSinceEpoch) > now - 30 * 86400000)
        .toList();
    final bwDelta30 = bw30.length > 1 ? bw30.last.w - bw30.first.w : null;
    final monthW =
        s.workouts.where((w) => w.d.substring(0, 7) == todayISO().substring(0, 7)).length;

    return AppPage(
      children: [
        PageHeader(
          title: t('Stats'),
          subtitle: t('Progress & history'),
          trailing: IconButtonRound('history', onTap: () => context.go('/history')),
        ),
        StatTiles(
          icons: const ['dumbbell', 'calendar', 'flame', 'scale'],
          tiles: [
            (label: t('Workouts'), value: '${s.workouts.length}', unit: null, color: null),
            (label: t('This month'), value: '$monthW', unit: null, color: null),
            (label: t('Week streak'), value: '${streakWeeks(s)}', unit: null, color: null),
            (
              label: t('Weight 30d'),
              value: bwDelta30 == null ? '—' : '${bwDelta30 > 0 ? '+' : ''}${fmtNum(bwDelta30)}',
              unit: bwDelta30 == null ? null : s.unit,
              color: bwDelta30 == null
                  ? null
                  : bwDeltaColor(context, bwDelta30, lastBW(s)?.w ?? 0, s.targetW),
            ),
          ],
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CardTitle(t('Activity — last 12 months'), note: t('by time trained')),
              const SizedBox(height: 12),
              Heatmap(
                state: s,
                // Straight to that day's recap — its totals and its sessions. It used to open
                // the whole month for a day with several, which answered a question nobody
                // asked by tapping a single square.
                onDay: (iso) {
                  if (workoutsOn(s, iso).isNotEmpty) daySummarySheet(iso);
                },
              ),
            ],
          ),
        ),
        if (s.workouts.isNotEmpty) MuscleBalanceCard(state: s),
        if (hasEffort(s)) EffortCard(state: s),
        _bodyWeightCard(context, s, now),
        if (s.meals.isNotEmpty) NutritionCard(state: s),
        _exerciseProgressCard(context, s),
        if (s.workouts.isNotEmpty) ...[
          Row(children: [
            Expanded(
              child: SecHeading(t('Recent workouts'),
                  margin: const EdgeInsets.fromLTRB(4, 22, 4, 10)),
            ),
            AppButton('${t('All')} ${s.workouts.length}',
                size: BtnSize.sm,
                variant: BtnVariant.ghost,
                trailingIcon: 'chevronRight',
                onTap: () => context.go('/history')),
          ]),
          AppList(children: [
            for (final w in s.workouts.reversed.take(6))
              WorkoutRow(workout: w, onTap: () => workoutDetailSheet(w)),
          ]),
        ],
      ],
    );
  }

  Widget _bodyWeightCard(BuildContext context, AppState s, int now) {
    final c = context.c;
    final points = [
      for (final b in s.bodyweight)
        if (_range == 0 || (b.t ?? dayOf(b.d).millisecondsSinceEpoch) > now - _range * 86400000)
          ChartPoint(t: b.t ?? dayOf(b.d).millisecondsSinceEpoch, y: b.w, d: b.d)
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(child: Text(t('Body weight'), style: ts(TypeScale.foot, color: c.label2))),
            AppButton(s.targetW != null ? fmtNum(s.targetW) : t('Goal'),
                size: BtnSize.sm,
                icon: 'target',
                color: s.targetW != null ? c.sys.yellow : null,
                onTap: goalSheet),
            const SizedBox(width: 8),
            AppButton(t('Log'), size: BtnSize.sm, icon: 'plus', onTap: () => bwSheet()),
          ]),
          const SizedBox(height: 10),
          Segmented<int>(
            value: _range,
            onChanged: (v) => setState(() => _range = v),
            options: [
              const SegOption(30, label: '1M'),
              const SegOption(90, label: '3M'),
              const SegOption(365, label: '1Y'),
              SegOption(0, label: t('All')),
            ],
          ),
          const SizedBox(height: 10),
          LineChart(points: points, height: 160, unit: s.unit, goal: s.targetW),
        ],
      ),
    );
  }

  /// One exercise's trend, read three ways: what you lifted, what that implies about a max,
  /// and how hard it felt. The three only mean something together — the same weight at a lower
  /// RIR is progress the top-set line alone draws flat.
  Widget _exerciseProgressCard(BuildContext context, AppState s) {
    final c = context.c;
    final kind = displayScale(s);
    final scaleLabel = scaleName(kind);

    final exHist = {for (final w in s.workouts) for (final e in w.entries) e.id}
        .where((id) => exdb[id] != null)
        .toList()
      ..sort((a, b) => exdb[a]!.n.compareTo(exdb[b]!.n));

    final curEx = (_exId != null && exHist.contains(_exId)) ? _exId! : exHist.firstOrNull;

    if (curEx == null) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _CardTitle(t('Exercise progress')),
            const SizedBox(height: 8),
            Text(t('Finish your first workout to see progress curves here.'),
                style: ts(TypeScale.foot, color: c.label2)),
          ],
        ),
      );
    }

    // How this exercise was logged most recently decides what the curve means: top weight,
    // longest hold or top speed. Sets logged in another mode lack the field and score 0, so a
    // switched exercise drops its old points instead of mixing seconds into a weight chart.
    var curMode = 'reps';
    for (var i = s.workouts.length - 1; i >= 0; i--) {
      final en = s.workouts[i].entries.where((e) => e.id == curEx).firstOrNull;
      if (en != null) {
        curMode = modeOf(en.cfg);
        break;
      }
    }
    final cardio = curMode == 'cardio';
    final timed = curMode == 'time';
    final exUnit = cardio ? 'km/h' : (timed ? 's' : s.unit);

    double metric(SetLog x) => cardio ? (x.speed ?? 0) : (timed ? (x.sec ?? 0) : (x.w ?? 0));

    final pts = <({int t, double y, String d, List<SetLog> sets, ExerciseConfig? target})>[];
    var exBest = 0.0;
    for (final w in s.workouts) {
      final en = w.entries.where((e) => e.id == curEx).firstOrNull;
      if (en == null) continue;
      final doneSets = en.sets.where((x) => x.done).toList();
      final mx = [
        ...doneSets.map(metric),
        if (!cardio && !timed) en.topW ?? 0,
        0.0,
      ].reduce((a, b) => a > b ? a : b);
      if (mx > 0) {
        pts.add((t: w.start, y: mx, d: w.d, sets: doneSets, target: en.target));
        if (mx > exBest) exBest = mx;
      }
    }

    final e1Pts = e1rmSeries(s, curEx);
    final e1Best = best1RM(s, curEx);
    final showE1 = e1Pts.isNotEmpty;

    final exRir = [for (final p in pts) avgRir(p.sets)];
    final showEff = exRir.whereType<double>().length >= 3;
    final onEff = showEff && _exMetric == 'effort';
    final onE1 = showE1 && _exMetric == 'e1rm';

    final topPts = [
      for (var i = 0; i < pts.length; i++)
        ChartPoint(
          t: pts[i].t,
          y: pts[i].y,
          d: pts[i].d,
          // 0 RIR (nothing left) is a full dot, 4+ a faint one; unrated sessions keep the
          // plain line.
          mark: exRir[i] == null ? null : 1 - (exRir[i]!.clamp(0, 4)) / 4,
          note: exRir[i] == null ? null : '$scaleLabel ${fmtNum(toScale(kind, exRir[i]))}',
        )
    ];
    final effPts = [
      for (var i = 0; i < pts.length; i++)
        if (exRir[i] != null)
          ChartPoint(t: pts[i].t, y: toScale(kind, exRir[i])!, d: pts[i].d)
    ];

    final options = <SegOption<String>>[
      SegOption('top', label: t('Top set')),
      if (showE1) SegOption('e1rm', label: t('Est. 1RM')),
      if (showEff) SegOption('effort', label: t('Effort')),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(t('Exercise progress')),
          const SizedBox(height: 10),
          Section(children: [
            SelectRow<String>(
              title: t('Exercise'),
              sheetTitle: t('Exercise progress'),
              value: curEx,
              onChanged: (v) => setState(() => _exId = v),
              options: [
                for (final id in exHist) SelectOption(id, capitalized(exdb[id]!.n)),
              ],
            ),
          ]),
          if (options.length > 1) ...[
            Segmented<String>(
              value: onEff ? 'effort' : (onE1 ? 'e1rm' : 'top'),
              onChanged: (v) => setState(() => _exMetric = v),
              options: options,
            ),
            const SizedBox(height: 10),
          ],
          LineChart(
            points: onEff
                ? effPts
                : (onE1
                    ? [for (final p in e1Pts) ChartPoint(t: p.t, y: p.y, d: p.d)]
                    : topPts),
            height: 150,
            unit: onEff ? scaleLabel : (onE1 ? s.unit : exUnit),
            color: onEff ? c.sys.yellow : c.sys.blue,
            invert: onEff && kind == 'rir',
          ),
          const SizedBox(height: 8),
          for (final p in pts.reversed.take(5))
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration:
                  BoxDecoration(border: Border(bottom: BorderSide(color: c.sep, width: R.hair))),
              child: Row(children: [
                Expanded(
                    child: Text(fmtDate(p.d, true),
                        style: ts(TypeScale.foot, color: c.label2))),
                Flexible(
                  child: Text(
                    p.sets.map((x) => setLabel(curEx, x, p.target)).join('  '),
                    textAlign: TextAlign.right,
                    style: ts(TypeScale.foot, color: c.label),
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: onEff
                    ? t('Average effort per workout')
                    : onE1
                        ? t('Estimated 1RM per workout')
                        : cardio
                            ? t('Top speed per workout')
                            : timed
                                ? t('Longest hold per workout')
                                : t('Best set weight per workout'),
              ),
              if (!onEff)
                TextSpan(children: [
                  TextSpan(text: ' · ${t('Best:')} '),
                  TextSpan(
                    text:
                        '${fmtNum(onE1 ? e1Best?.est : exBest)} ${onE1 ? s.unit : exUnit}',
                    style: ts(TypeScale.foot, color: c.acc, weight: FontWeight.w600),
                  ),
                ]),
            ]),
            style: ts(TypeScale.foot, color: c.label3),
          ),
          if (onE1 && e1Best != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                t('Best estimate from {0} on {1} — an estimate, not a tested max.',
                    '${fmtNum(e1Best.w)} ${s.unit} × ${e1Best.r}', fmtDate(e1Best.d, true)),
                style: ts(TypeScale.foot, color: c.label3),
              ),
            ),
          if (!onEff && !onE1 && showEff)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                t('A fuller dot means less left in the tank — the same weight at a lower {0} is progress the line alone does not show.',
                    scaleLabel),
                style: ts(TypeScale.foot, color: c.label3),
              ),
            ),
        ],
      ),
    );
  }
}

/// A card heading, with an optional quieter note after it.
class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, {this.note});

  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: title),
        if (note != null)
          TextSpan(text: ' · $note', style: ts(TypeScale.foot, color: c.label3)),
      ]),
      style: ts(TypeScale.foot, color: c.label2),
    );
  }
}

/// Which muscles the training in a window actually hit — and, the point of the card, which
/// ones it keeps missing. Shading is relative within the window.
class MuscleBalanceCard extends StatefulWidget {
  const MuscleBalanceCard({super.key, required this.state});

  final AppState state;

  @override
  State<MuscleBalanceCard> createState() => _MuscleBalanceCardState();
}

class _MuscleBalanceCardState extends State<MuscleBalanceCard> {
  int _win = 7;
  bool _hard = false;
  String? _sel;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.state;
    final now = DateTime.now().millisecondsSinceEpoch;

    final inWin = s.workouts.where((w) {
      if (_win == 0) return true;
      if (_win == 7) return weekKey(w.d) == weekKey(todayISO());
      return (w.start != 0 ? w.start : dayOf(w.d).millisecondsSinceEpoch) >
          now - _win * 86400000;
    }).toList();

    // Counting only the sets taken near failure turns the map from "where did the volume go"
    // into "where did the stimulus go" — a muscle can lead on sets and still never be trained
    // hard. Offered only when the window holds ratings at all, since with none the hard map
    // would just be empty and read as "you trained nothing".
    final rated = inWin.any((w) => w.entries.any((e) => e.sets.any((x) => x.done && isHardSet(x))));
    final on = _hard && rated;
    final load = loadOfWorkouts(inWin, on ? isHardSet : null);
    final ranked = rankOf(load);
    final top = ranked.worked.take(4).toList();
    final max = ranked.worked.isEmpty ? 0.0 : load[ranked.worked.first]!;
    double sets(String m) => ((load[m] ?? 0) * 10).round() / 10;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: _CardTitle(t('Muscle balance'),
                  note: on ? t('by hard sets') : t('by sets worked')),
            ),
            if (rated)
              AppButton(on ? t('Hard') : t('All'),
                  size: BtnSize.sm,
                  icon: 'flame',
                  color: on ? c.sys.yellow : null,
                  onTap: () => setState(() {
                        _hard = !_hard;
                        _sel = null;
                      })),
          ]),
          const SizedBox(height: 10),
          Segmented<int>(
            value: _win,
            onChanged: (v) => setState(() {
              _win = v;
              _sel = null;
            }),
            options: [
              SegOption(7, label: t('Week')),
              const SegOption(30, label: '30d'),
              const SegOption(90, label: '90d'),
              SegOption(0, label: t('All')),
            ],
          ),
          const SizedBox(height: 10),
          if (inWin.isEmpty)
            Text(t('No workouts in this period yet.'), style: ts(TypeScale.foot, color: c.label2))
          else ...[
            BodyMap(
              load: load,
              body: s.body,
              selected: _sel,
              onMuscle: (m) => setState(() => _sel = _sel == m ? null : m),
            ),
            const BodyMapLegend(),
            if (_sel != null)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.only(top: 10),
                decoration:
                    BoxDecoration(border: Border(top: BorderSide(color: c.sep, width: R.hair))),
                child: Row(children: [
                  Expanded(
                    child: Text(t(muscleName[_sel]!),
                        style: ts(TypeScale.sub, color: c.label, weight: FontWeight.w600)),
                  ),
                  Text(
                    sets(_sel!) > 0
                        ? t('{0} sets', fmtNum(sets(_sel!)))
                        : (on ? t('no hard sets') : t('not trained')),
                    style: ts(TypeScale.cap, color: c.label2),
                  ),
                ]),
              )
            else
              for (final m in top)
                _MuscleRow(
                  name: t(muscleName[m]!),
                  fraction: max == 0 ? 0 : load[m]! / max,
                  value: t('{0} sets', fmtNum(sets(m))),
                  color: on ? c.sys.yellow : c.acc,
                ),
            if (ranked.missed.isNotEmpty) ...[
              SecHeading(
                  on ? t('No hard sets in this period') : t('Not trained in this period'),
                  margin: const EdgeInsets.fromLTRB(4, 12, 4, 8)),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final m in ranked.missed) MuscleChip(t(muscleName[m]!), miss: true),
              ]),
            ] else if (ranked.worked.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  on
                      ? t('Every muscle group got at least one hard set in this period.')
                      : t('Every muscle group got some work in this period.'),
                  style: ts(TypeScale.foot, color: c.label2),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MuscleRow extends StatelessWidget {
  const _MuscleRow(
      {required this.name, required this.fraction, required this.value, required this.color});

  final String name;
  final double fraction;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
          child: Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: ts(TypeScale.sub, size: 14, color: c.label)),
        ),
        const SizedBox(width: 9),
        Container(
          width: 74,
          height: 5,
          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(3)),
          clipBehavior: Clip.antiAlias,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction.clamp(0, 1),
              child: DecoratedBox(
                  decoration:
                      BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
            ),
          ),
        ),
        const SizedBox(width: 9),
        SizedBox(
          width: 52,
          child: Text(value,
              textAlign: TextAlign.right, style: ts(TypeScale.cap, color: c.label2)),
        ),
      ]),
    );
  }
}

/// How hard the training was — the half of the picture a volume chart cannot show.
///
/// Every number carries how much of the training it speaks for: rating is optional and off by
/// default, so a partly rated history is the normal case, and an average without its
/// denominator would quietly speak for sets that were never rated.
class EffortCard extends StatefulWidget {
  const EffortCard({super.key, required this.state});

  final AppState state;

  @override
  State<EffortCard> createState() => _EffortCardState();
}

class _EffortCardState extends State<EffortCard> {
  int _win = 90;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = widget.state;
    final kind = displayScale(s);
    final hd = scaleName(kind);
    final sum = effortSummary(s, _win);
    final weeks = effortWeeks(s, _win);
    final hist = effortHistogram(s, _win);
    final maxBin = [1, ...hist.map((b) => b.n)].reduce((a, b) => a > b ? a : b);

    // The week's set count rides along in the tooltip, because the pair is the reading: volume
    // up with effort up is fatigue piling up, volume up with effort flat is adaptation.
    final pts = [
      for (final w in weeks)
        ChartPoint(t: w.t, y: toScale(kind, w.rir)!, note: t('{0} sets', w.sets))
    ];

    // Bins run hardest-first in both scales: RIR 0 and RPE 10 are the same set.
    String binLabel(EffortBin b) => kind == 'rpe'
        ? (b.tail ? '≤ 6' : '${10 - b.rir}')
        : (b.tail ? '${b.rir}+' : '${b.rir}');

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTitle(t('Effort'), note: t('how close to failure')),
          const SizedBox(height: 10),
          Segmented<int>(
            value: _win,
            onChanged: (v) => setState(() => _win = v),
            options: [
              const SegOption(30, label: '30d'),
              const SegOption(90, label: '90d'),
              const SegOption(365, label: '1Y'),
              SegOption(0, label: t('All')),
            ],
          ),
          const SizedBox(height: 10),
          if (sum.rated == 0)
            Text(t('No rated sets in this period.'), style: ts(TypeScale.foot, color: c.label2))
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        sum.avg == null ? '—' : '${fmtNum(toScale(kind, sum.avg))} $hd',
                        style: ts(TypeScale.title,
                            size: 26, color: c.label, weight: FontWeight.w600),
                      ),
                      Text(t('average effort'), style: ts(TypeScale.foot, color: c.label3)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sum.hardPct == null ? '—' : '${(sum.hardPct! * 100).round()}%',
                      style: ts(TypeScale.title,
                          size: 26, color: c.sys.yellow, weight: FontWeight.w600),
                    ),
                    Text(t('at {0} {1} or harder', hd, fmtNum(toScale(kind, hardRir))),
                        style: ts(TypeScale.foot, color: c.label3)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(t('{0} of {1} finished sets rated', sum.rated, sum.done),
                style: ts(TypeScale.foot, color: c.label3)),
            if (effortOf(s) == 'none')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  t('Effort per set is switched off — turn it on in Settings to keep rating.'),
                  style: ts(TypeScale.foot, color: c.sys.yellow),
                ),
              ),
            if (pts.length > 1) ...[
              SecHeading(t('Week by week'), margin: const EdgeInsets.fromLTRB(4, 12, 4, 8)),
              LineChart(
                points: pts,
                height: 140,
                unit: hd,
                color: c.sys.yellow,
                invert: kind == 'rir',
              ),
            ],
            SecHeading(t('Where the sets land'), margin: const EdgeInsets.fromLTRB(4, 12, 4, 8)),
            for (final b in hist)
              _MuscleRow(
                name: '$hd ${binLabel(b)}',
                fraction: b.n / maxBin,
                value: b.n > 0 ? '${b.n} · ${(b.pct * 100).round()}%' : '—',
                color: b.rir <= hardRir ? c.sys.yellow : c.label3,
              ),
            const SizedBox(height: 8),
            Text(
              t('Most working sets belong close to failure without living there — half at the floor and half at the top average out to a healthy-looking middle.'),
              style: ts(TypeScale.foot, color: c.label3),
            ),
          ],
        ],
      ),
    );
  }
}


/// What the food log says, and whether the scale agrees with it.
///
/// The second half is the one worth having. Everything upstream — a BMR equation, a MET table
/// inferred from a body part, a portion size somebody eyeballed — is an estimate, and a screen
/// that showed only the prediction would be asking to be believed. Showing the residual against
/// the scale turns the whole feature into something that can be checked, and tells the user the
/// only thing that actually generalises: whether these numbers run high or low for them.
class NutritionCard extends StatelessWidget {
  const NutritionCard({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final s = state;
    final iso = todayISO();
    final week = weekTotals(s, iso);
    final target = macroTargets(s, iso: iso);
    final ev = evolution(s);

    // One point per day that has any food on it, over the last 90 days.
    final days = <String>{for (final m in s.meals) m.d}.toList()..sort();
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    final points = <ChartPoint>[
      for (final d in days)
        if (!dayOf(d).isBefore(cutoff))
          ChartPoint(t: dayOf(d).millisecondsSinceEpoch, y: dayTotals(s, d).kcal, d: d),
    ];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionTitle(t('Nutrition')),
          if (points.isNotEmpty)
            LineChart(
              points: points,
              height: 150,
              unit: t('kcal'),
              goal: target?.kcal,
            ),
          const SizedBox(height: 14),
          Text(t('This week'), style: ts(TypeScale.foot, color: c.label2)),
          const SizedBox(height: 6),
          MacroLegend(macros: week),
          if (ev != null) ...[
            const SizedBox(height: 16),
            Container(height: R.hair, color: c.sep),
            const SizedBox(height: 14),
            Text(t('Plan against scale'), style: ts(TypeScale.foot, color: c.label2)),
            const SizedBox(height: 8),
            _EvRow(
              label: t('Your log predicted'),
              value: '${_signed(ev.predicted)} kg',
              tint: c.label,
            ),
            _EvRow(
              label: t('The scale says'),
              value: '${_signed(ev.observed)} kg',
              tint: c.label,
            ),
            const SizedBox(height: 8),
            Text(
              _verdict(ev),
              style: ts(TypeScale.cap, color: ev.reliable ? c.label2 : c.label3),
            ),
          ],
        ],
      ),
    );
  }

  static String _signed(double v) =>
      '${v > 0 ? '+' : v < 0 ? '-' : ''}${fmtNum(v.abs())}';

  /// Says what the gap means in the only terms that are actionable.
  static String _verdict(Evolution ev) {
    if (!ev.reliable) {
      return t('Keep logging — a fortnight of days and weigh-ins is about where this starts to mean anything.');
    }
    // Half a kilo over the window is inside what water alone moves.
    if (ev.gap.abs() < 0.5) {
      return t('Close enough. What you log and what you weigh are telling the same story.');
    }
    return ev.gap > 0
        ? t('The scale is {0} kg above what your log predicted. Either some food is going unlogged, or the app is being generous about what you burn — lowering the target is the safer read.', fmtNum(ev.gap.abs()))
        : t('You are {0} kg below what your log predicted. You are burning more than the app assumes, so there is room to eat a little more.', fmtNum(ev.gap.abs()));
  }
}

class _EvRow extends StatelessWidget {
  const _EvRow({required this.label, required this.value, required this.tint});

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: ts(TypeScale.foot, color: c.label2))),
        Text(value, style: ts(TypeScale.body, color: tint, weight: FontWeight.w600)),
      ]),
    );
  }
}
