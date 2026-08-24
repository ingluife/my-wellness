import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_open_gym/data/models/app_state.dart';
import 'package:my_open_gym/domain/exercises.dart';
import 'package:my_open_gym/state/app_state_provider.dart';
import 'package:my_open_gym/ui/app.dart';
import 'package:my_open_gym/ui/widgets/tab_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
    await Exercises.instance.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the app boots into Home with the tab bar available', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyOpenGymApp()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AppTabBar), findsOneWidget);
    // The tab bar is always the way out of a screen, so it must be there from the first frame.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('the accent and theme in the profile drive the whole app', (tester) async {
    final container = ProviderContainer();
    container.read(appStateProvider.notifier).replaceState(
          AppState.defaults()
            ..theme = 'light'
            ..accent = 'violet',
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MyOpenGymApp()),
    );
    await tester.pumpAndSettle();

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.theme!.brightness, Brightness.light);
    // Light-theme purple, not the dark one — an accent is an alias onto the system palette.
    expect(app.theme!.colorScheme.primary, const Color(0xFFAF52DE));

    // Disposed inside the test body, not in a teardown: the repository's debounced write is
    // a live timer, and the widget binding checks for those before user teardowns run.
    container.dispose();
  });

  testWidgets('a running workout turns the Start disc into Resume', (tester) async {
    final container = ProviderContainer();
    container.read(appStateProvider.notifier).replaceState(
          AppState.defaults()
            ..active = ActiveWorkout(id: 'a', d: '2026-08-24', start: 0, name: 'Push Day'),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MyOpenGymApp()),
    );
    await tester.pump();

    // Home's today-row and the tab bar's disc both say Resume once a session is running.
    expect(find.text('Resume'), findsNWidgets(2));
    expect(find.text('Start'), findsNothing);

    container.dispose();
  });
}
