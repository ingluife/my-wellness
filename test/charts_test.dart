import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/ui/theme/app_theme.dart';
import 'package:my_wellness/ui/theme/tokens.dart';
import 'package:my_wellness/ui/widgets/heatmap.dart';
import 'package:my_wellness/ui/widgets/line_chart.dart';
import 'package:my_wellness/ui/widgets/macro_bar.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
  });

  Widget host(Widget child, {Brightness b = Brightness.dark}) => MaterialApp(
        theme: buildTheme(b, Accent.lime),
        home: Scaffold(body: Center(child: SizedBox(width: 340, child: child))),
      );

  int day(int n) =>
      DateTime.now().subtract(Duration(days: n)).millisecondsSinceEpoch;

  testWidgets('a curve paints, in both themes', (tester) async {
    for (final b in Brightness.values) {
      await tester.pumpWidget(host(
        LineChart(
          points: [
            ChartPoint(t: day(90), y: 82.4),
            ChartPoint(t: day(60), y: 81.0),
            ChartPoint(t: day(30), y: 79.8),
            ChartPoint(t: day(1), y: 78.3),
          ],
          unit: 'kg',
          goal: 77,
        ),
        b: b,
      ));
      expect(tester.takeException(), isNull, reason: b.name);
    }
  });

  testWidgets('an empty series says so rather than painting an empty frame', (tester) async {
    await tester.pumpWidget(host(const LineChart(points: [])));
    expect(find.text('No data yet'), findsOneWidget);
  });

  testWidgets('a single point still draws a chart', (tester) async {
    await tester.pumpWidget(host(LineChart(points: [ChartPoint(t: day(3), y: 80)])));
    expect(tester.takeException(), isNull);
    expect(find.text('No data yet'), findsNothing);
  });

  testWidgets('marked points and an inverted axis both paint', (tester) async {
    await tester.pumpWidget(host(LineChart(
      points: [
        ChartPoint(t: day(20), y: 2, mark: 0.5, note: 'RIR 2'),
        ChartPoint(t: day(10), y: 1, mark: 1),
        ChartPoint(t: day(2), y: 3, mark: 0),
      ],
      invert: true,
      unit: 'RIR',
    )));
    expect(tester.takeException(), isNull);
  });

  testWidgets('touching the curve shows the point it is nearest', (tester) async {
    await tester.pumpWidget(host(LineChart(
      points: [
        ChartPoint(t: day(30), y: 60, d: '2026-07-25'),
        ChartPoint(t: day(2), y: 65, d: '2026-08-22'),
      ],
      unit: 'kg',
    )));
    await tester.tapAt(tester.getCenter(find.byType(LineChart)) + const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('65 kg'), findsOneWidget);
  });

  testWidgets('the heatmap paints a year and its legend', (tester) async {
    final s = AppState(workouts: [
      Workout(
          id: 'w1',
          d: '2026-08-20',
          start: day(4),
          end: day(4) + 3600000,
          name: 'Push Day',
          vol: 7535),
    ]);
    await tester.pumpWidget(host(Heatmap(state: s)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Less time'), findsOneWidget);
    expect(find.text('More time'), findsOneWidget);
    expect(find.text('Mon'), findsOneWidget);
  });

  testWidgets('an untrained profile still gets a grid', (tester) async {
    await tester.pumpWidget(host(Heatmap(state: AppState())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('macros', () {
    const target = (kcal: 2400.0, p: 160.0, c: 260.0, f: 67.0);

    testWidgets('the ring paints under, at and over target, in both themes', (tester) async {
      for (final b in Brightness.values) {
        for (final eaten in [0.0, 1200.0, 2400.0, 3100.0]) {
          await tester.pumpWidget(host(
            KcalRing(eaten: eaten, target: target.kcal),
            b: b,
          ));
          expect(tester.takeException(), isNull, reason: '$eaten in ${b.name}');
        }
      }
    });

    testWidgets('a zero target does not divide by it', (tester) async {
      await tester.pumpWidget(host(const KcalRing(eaten: 500, target: 0)));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the bars paint with and without a target', (tester) async {
      const eaten = (kcal: 1800.0, p: 120.0, c: 190.0, f: 52.0);
      for (final b in Brightness.values) {
        await tester.pumpWidget(host(
          const MacroBars(eaten: eaten, target: target),
          b: b,
        ));
        expect(tester.takeException(), isNull, reason: b.name);

        // A day logged before a profile existed has totals but nothing to measure against.
        await tester.pumpWidget(host(const MacroBars(eaten: eaten, target: null), b: b));
        expect(tester.takeException(), isNull, reason: b.name);
      }
    });

    testWidgets('the split handles an empty meal without a zero-width flex', (tester) async {
      await tester.pumpWidget(
          host(const MacroSplit(macros: (kcal: 0.0, p: 0.0, c: 0.0, f: 0.0))));
      expect(tester.takeException(), isNull);

      // Pure fat: two of the three segments are genuinely zero.
      await tester.pumpWidget(
          host(const MacroSplit(macros: (kcal: 900.0, p: 0.0, c: 0.0, f: 100.0))));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the legend paints in both themes', (tester) async {
      for (final b in Brightness.values) {
        await tester.pumpWidget(host(const MacroLegend(macros: target), b: b));
        expect(tester.takeException(), isNull, reason: b.name);
      }
    });

    testWidgets('the donut paints for a real split and for an empty food, in both themes',
        (tester) async {
      for (final b in Brightness.values) {
        await tester.pumpWidget(host(const MacroDonut(macros: target), b: b));
        expect(tester.takeException(), isNull, reason: b.name);

        // No macros at all falls back to a bare track rather than dividing by zero.
        await tester.pumpWidget(
            host(const MacroDonut(macros: (kcal: 0.0, p: 0.0, c: 0.0, f: 0.0)), b: b));
        expect(tester.takeException(), isNull, reason: b.name);
      }
    });

    testWidgets('the rows paint the macros and any extras, in both themes', (tester) async {
      for (final b in Brightness.values) {
        await tester.pumpWidget(host(
          const MacroRows(macros: target, extras: [(label: 'Fibre', g: 8.0)]),
          b: b,
        ));
        expect(tester.takeException(), isNull, reason: b.name);
        expect(find.textContaining('160'), findsOneWidget, reason: b.name);
      }
    });
  });
}
