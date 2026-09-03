import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/exercises.dart';
import 'package:my_wellness/domain/format.dart';
import 'package:my_wellness/state/app_state_provider.dart';
import 'package:my_wellness/ui/app.dart';
import 'package:my_wellness/ui/widgets/controls/surfaces.dart';
import 'package:my_wellness/ui/widgets/line_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
    await Exercises.instance.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// [settle] is off while a workout is running: the tab bar's Start disc pulses forever by
  /// design, so `pumpAndSettle` would never return.
  Future<ProviderContainer> pump(WidgetTester tester,
      [AppState? initial, bool settle = true]) async {
    final container = ProviderContainer();
    if (initial != null) container.read(appStateProvider.notifier).replaceState(initial);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyWellnessApp()));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }
    return container;
  }

  testWidgets('an empty profile is invited to start, not shown empty charts', (tester) async {
    final container = await pump(tester);
    expect(find.text('Welcome!'), findsOneWidget);
    expect(find.text('Load starter plan (PPL)'), findsOneWidget);
    expect(
        find.textContaining('No entries yet — log your weight to start the curve'), findsOneWidget);
    // The streak used to be one sentence ('0 week streak'); it is a stat tile now, with the
    // label and the number as separate widgets — this checks a fresh profile still reads as
    // zero rather than as broken or missing data.
    expect(find.text('Week streak'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    container.dispose();
  });

  testWidgets('a rest day says so instead of offering a session', (tester) async {
    final container = await pump(tester, AppState.defaults()..routines.add(Routine(id: 'r', name: 'Push Day')));
    expect(find.text('Rest day'), findsOneWidget);
    // The welcome card is gone once there is a routine.
    expect(find.text('Welcome!'), findsNothing);
    container.dispose();
  });

  testWidgets("today's routine is offered with a Start tag", (tester) async {
    final routine = Routine(id: 'r', name: 'Push Day');
    final s = AppState.defaults()
      ..routines.add(routine)
      ..week['${jsDay(DateTime.now())}'] = 'r';
    final container = await pump(tester, s);

    expect(find.text('Push Day'), findsOneWidget);
    expect(find.widgetWithText(Tag, 'Start'), findsOneWidget);
    container.dispose();
  });

  testWidgets('a running workout is offered as Resume', (tester) async {
    final s = AppState.defaults()
      ..active = ActiveWorkout(id: 'a', d: todayISO(), start: 0, name: 'Push Day');
    final container = await pump(tester, s, false);
    expect(find.text('Push Day — in progress'), findsOneWidget);
    expect(find.widgetWithText(Tag, 'Resume'), findsOneWidget);
    container.dispose();
  });

  testWidgets('logged weight draws the curve and its delta', (tester) async {
    final s = AppState.defaults()
      ..bodyweight.addAll([
        BodyWeightEntry(d: '2026-08-20', w: 80.0, t: dayOf('2026-08-20').millisecondsSinceEpoch),
        BodyWeightEntry(d: '2026-08-23', w: 78.4, t: dayOf('2026-08-23').millisecondsSinceEpoch),
      ])
      ..targetW = 77;
    final container = await pump(tester, s);

    // Once on the weight curve's own headline, and once in the snapshot grid's "Body weight"
    // tile, which renders its number apart from the unit so long values never need an ellipsis.
    expect(find.text('78.4'), findsNWidgets(2));
    // The move since the previous weigh-in, as a magnitude with an arrow beside it.
    expect(find.text('1.6'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
    expect(find.textContaining('Goal 77 kg'), findsOneWidget);
    container.dispose();
  });

  testWidgets('the week strip shows seven days and marks today', (tester) async {
    final container = await pump(tester);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('${DateTime.now().day}'), findsWidgets);
    container.dispose();
  });
}
