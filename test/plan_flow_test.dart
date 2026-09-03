import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/exercises.dart';
import 'package:my_wellness/state/app_state_provider.dart';
import 'package:my_wellness/ui/app.dart';
import 'package:my_wellness/ui/widgets/controls/surfaces.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plan and RoutineEdit, driven the way a person drives them.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
    await Exercises.instance.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Scroll the target into view before tapping it. The test viewport is 800px tall and these
  /// screens are long — a button below the fold is a real widget that simply is not under the
  /// finger yet.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<ProviderContainer> pumpApp(WidgetTester tester, {AppState? initial}) async {
    final container = ProviderContainer();
    if (initial != null) container.read(appStateProvider.notifier).replaceState(initial);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MyWellnessApp()),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('an empty plan offers the starter plan, and loading it fills the week',
      (tester) async {
    final container = await pumpApp(tester);
    await tester.tap(find.text('Plan').last);
    await tester.pumpAndSettle();

    expect(find.text('No routines yet.'), findsOneWidget);
    await tapVisible(tester, find.text('Load starter plan (Push / Pull / Legs)'));

    final s = container.read(appStateProvider);
    expect(s.routines.map((r) => r.name), ['Push Day', 'Pull Day', 'Leg Day']);
    // Mon Push, Wed Pull, Fri Legs — the week the toast promises.
    expect(s.week['1'], s.routines[0].id);
    expect(s.week['3'], s.routines[1].id);
    expect(s.week['5'], s.routines[2].id);

    expect(find.text('Push Day'), findsWidgets);
    expect(find.text('6 exercises'), findsWidgets);

    container.dispose();
  });

  testWidgets('every weekday shows what it holds, Monday first', (tester) async {
    final container = await pumpApp(tester);
    await tester.tap(find.text('Plan').last);
    await tester.pumpAndSettle();

    // Seven rows, all Rest until something is scheduled.
    expect(find.widgetWithText(Tag, 'Rest'), findsNWidgets(7));
    expect(find.text('Monday'), findsOneWidget);
    expect(find.text('Sunday'), findsOneWidget);

    container.dispose();
  });

  testWidgets('assigning a routine to a day writes it into the weekly plan', (tester) async {
    final routine = Routine(id: 'r1', name: 'Push Day');
    final container = await pumpApp(
      tester,
      initial: AppState.defaults()..routines.add(routine),
    );
    await tester.tap(find.text('Plan').last);
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('Tuesday'));
    // The sheet lists Rest plus every routine.
    await tester.tap(find.text('Push Day').last);
    await tester.pumpAndSettle();

    expect(container.read(appStateProvider).week['2'], 'r1');
    container.dispose();
  });

  testWidgets('a routine opens its editor, and deleting it clears its day', (tester) async {
    final routine = Routine(id: 'r1', name: 'Push Day');
    final container = await pumpApp(
      tester,
      initial: AppState.defaults()
        ..routines.add(routine)
        ..week['1'] = 'r1',
    );
    await tester.tap(find.text('Plan').last);
    await tester.pumpAndSettle();

    // Monday's schedule row also names the routine in its tag, so the routine list's own row
    // is the later of the two.
    await tapVisible(tester, find.widgetWithText(ListItem, 'Push Day').last);
    expect(find.text('No exercises yet — add your first one.'), findsOneWidget);

    await tapVisible(tester, find.text('Delete routine'));
    await tapVisible(tester, find.text('Delete'));

    final s = container.read(appStateProvider);
    expect(s.routines, isEmpty);
    // The day it was scheduled on goes back to being a rest day rather than a dangling id.
    expect(s.week['1'], isNull);

    container.dispose();
  });
}
