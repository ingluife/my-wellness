import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_open_gym/data/models/app_state.dart';
import 'package:my_open_gym/ui/theme/app_theme.dart';
import 'package:my_open_gym/ui/theme/tokens.dart';
import 'package:my_open_gym/ui/widgets/heatmap.dart';
import 'package:my_open_gym/ui/widgets/line_chart.dart';

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
}
