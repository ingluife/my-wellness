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

  group("today's card reports the whole day", () {
    /// A finished session on [d], carrying a stamped volume the way `doFinishWorkout` leaves it.
    Workout done(String id, {required double vol, int min = 45, String? d}) {
      final start = DateTime.now().millisecondsSinceEpoch - min * 60000;
      return Workout(
        id: id,
        d: d ?? todayISO(),
        start: start,
        end: start + min * 60000,
        name: id,
        vol: vol,
      );
    }

    testWidgets('one session is named, and shows its own numbers', (tester) async {
      final s = AppState.defaults()..workouts.add(done('Push Day', vol: 4000));
      final container = await pump(tester, s);

      expect(find.text('Push Day'), findsWidgets);
      expect(find.text('4,000'), findsOneWidget);
      container.dispose();
    });

    testWidgets('two sessions are summed, not reduced to the latest', (tester) async {
      // The bug: the card used to keep only the latest-ending session, so half of a two-a-day
      // was missing from the screen with nothing to say so.
      final s = AppState.defaults()
        ..workouts.addAll([
          done('Morning', vol: 4000, min: 45),
          done('Evening', vol: 1500, min: 30),
        ]);
      final container = await pump(tester, s);

      expect(find.text('5,500'), findsOneWidget, reason: '4,000 + 1,500');
      expect(find.text('1,500'), findsNothing, reason: 'the later session alone');
      container.dispose();
    });

    testWidgets('two sessions are counted rather than naming only one of them', (tester) async {
      final s = AppState.defaults()
        ..workouts.addAll([done('Morning', vol: 4000), done('Evening', vol: 1500)]);
      final container = await pump(tester, s);

      expect(find.text('2 sessions'), findsOneWidget);
      expect(find.text('Evening'), findsNothing);
      container.dispose();
    });

    testWidgets('tapping the total opens the day, not one of its sessions', (tester) async {
      final s = AppState.defaults()
        ..workouts.addAll([done('Morning', vol: 4000), done('Evening', vol: 1500)]);
      final container = await pump(tester, s);

      await tester.tap(find.text('5,500'));
      await tester.pumpAndSettle();

      // The day recap lists both sessions; the single-session detail sheet could only show one.
      expect(find.text('Morning'), findsOneWidget);
      expect(find.text('Evening'), findsOneWidget);
      container.dispose();
    });

    testWidgets('a past day with a single session still opens its recap', (tester) async {
      // Going straight to the session detail is what made that day's macros and weigh-in
      // unreachable — the recap is the only place they are shown.
      final yesterday = isoOf(DateTime.now().subtract(const Duration(days: 1)));
      final s = AppState.defaults()
        ..workouts.add(done('Leg Day', vol: 3000, d: yesterday))
        ..bodyweight.add(BodyWeightEntry(d: yesterday, w: 78.4));
      final container = await pump(tester, s);

      // Tapped by the cell's weekday letter, which is unique in the strip — the day number is
      // not, so a bare number finder can land on a stat tile instead.
      await tester.tap(find.text(days[jsDay(dayOf(yesterday))].toUpperCase()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Trained'), findsOneWidget);
      // The session is a row in the recap, one tap from its own detail...
      expect(find.text('Leg Day'), findsOneWidget);
      // ...and the day's totals and weigh-in — the things going straight to the detail hid.
      expect(find.text('3,000'), findsOneWidget);
      expect(find.text('78.4 kg'), findsOneWidget);
      container.dispose();
    });
  });
}
