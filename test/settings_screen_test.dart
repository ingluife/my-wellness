import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_open_gym/data/models/app_state.dart';
import 'package:my_open_gym/domain/exercises.dart';
import 'package:my_open_gym/state/app_state_provider.dart';
import 'package:my_open_gym/ui/app.dart';
import 'package:my_open_gym/ui/sheets/sheet_service.dart';
import 'package:my_open_gym/ui/widgets/controls/surfaces.dart';
import 'package:my_open_gym/ui/widgets/tab_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings as a hub.
///
/// The screen used to hold twenty-three rows in one scroll. What these tests pin is the deal
/// that replaced it: the top level is short, every row that leads somewhere says what it
/// currently holds, and nothing that used to be settable stopped being settable on the way.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
    await Exercises.instance.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(WidgetTester tester, AppState? initial, String route) async {
    final container = ProviderContainer();
    if (initial != null) container.read(appStateProvider.notifier).replaceState(initial);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyOpenGymApp()));
    await tester.pumpAndSettle();
    appNavigatorKey.currentContext!.go(route);
    await tester.pumpAndSettle();
    return container;
  }

  String path() => GoRouter.of(appNavigatorKey.currentContext!).state.uri.path;

  testWidgets('the hub fits a phone without scrolling', (tester) async {
    // The whole point of the restructure. `skipOffstage: false` is deliberately *not* used
    // here: a row that only a scroll can reach has not met the claim this test makes.
    //
    // 430x932 rather than a narrower phone because every screen in the app — Home and Plan
    // included, and on the code as it stood before this one was touched — overflows a
    // horizontal box by 3px at 390 wide. That is worth fixing, but it is not this test's claim,
    // and failing here would report it as one.
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = await pump(tester, AppState.defaults(), '/settings');

    for (final row in ['Language', 'Weight unit', 'Appearance', 'During a workout',
      'Workout day reminder', 'AI providers', 'Your data']) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    container.dispose();
  });

  testWidgets('every row that leads somewhere says what it holds', (tester) async {
    final s = AppState.defaults()
      ..theme = 'light'
      ..restSec = 120
      ..effort = 'rpe';
    final container = await pump(tester, s, '/settings');

    expect(find.text('Light'), findsOneWidget, reason: 'appearance summary');
    expect(find.text('120s · RPE'), findsOneWidget, reason: 'workout summary');
    expect(find.text('Off'), findsOneWidget, reason: 'ai summary');
    // The promise the old screen opened with, now carried by the row that leads to everything
    // capable of moving the log off the device.
    expect(find.text('All data stays on this phone'), findsOneWidget);
    container.dispose();
  });

  testWidgets('the workout summary drops the effort half when it is off', (tester) async {
    final container =
        await pump(tester, AppState.defaults()..restSec = 90..effort = 'none', '/settings');
    expect(find.text('90s'), findsOneWidget);
    container.dispose();
  });

  testWidgets('each row opens its screen, and each screen comes back', (tester) async {
    final moved = {
      'Appearance': ('/settings/appearance', 'Accent color'),
      'During a workout': ('/settings/workout', 'Rest timer'),
      'Your data': ('/settings/data', 'Reset everything'),
    };

    for (final e in moved.entries) {
      final container = await pump(tester, AppState.defaults(), '/settings');

      // The default test surface is 800x600, shorter than any phone, so the last row of the hub
      // sits below it here even though it does not on a real device.
      final row = find.text(e.key, skipOffstage: false);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(path(), e.value.$1, reason: e.key);
      // The control genuinely moved rather than being left behind on the hub.
      expect(find.text(e.value.$2, skipOffstage: false), findsOneWidget, reason: e.key);

      await tester.tap(find.byType(IconButtonRound).first);
      await tester.pumpAndSettle();
      expect(path(), '/settings', reason: '${e.key} back');
      container.dispose();
    }
  });

  testWidgets('a setting changed on a sub-screen shows up on the hub', (tester) async {
    final container = await pump(tester, AppState.defaults(), '/settings/appearance');

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(container.read(appStateProvider).theme, 'light');

    appNavigatorKey.currentContext!.go('/settings');
    await tester.pumpAndSettle();
    expect(find.text('Light'), findsOneWidget);
    container.dispose();
  });

  testWidgets('the reminder time row appears only once the reminder is on', (tester) async {
    var container = await pump(tester, AppState.defaults(), '/settings');
    expect(find.text('Reminder time'), findsNothing);
    container.dispose();

    final on = AppState.defaults()..reminder.on = true;
    container = await pump(tester, on, '/settings');
    expect(find.text('Reminder time'), findsOneWidget);
    expect(find.text(on.reminder.time), findsOneWidget);
    container.dispose();
  });

  testWidgets('Settings and its sub-screens all keep Home lit', (tester) async {
    for (final p in ['/settings', '/settings/workout', '/settings/appearance',
      '/settings/data', '/settings/ai']) {
      final container = await pump(tester, AppState.defaults(), p);
      final tab = tester.widget<AppTabBar>(find.byType(AppTabBar));
      expect(tab.current, 'settings', reason: p);
      container.dispose();
    }
  });

  testWidgets('the exercise catalogue is reachable from Plan, and lights Plan', (tester) async {
    // The tab bar gave the catalogue's slot to Nutrition, so this row is now its only door.
    // If it stops working the screen is not broken — it is simply gone.
    final container = await pump(tester, AppState.defaults(), '/plan');

    final row = find.text('Exercises', skipOffstage: false);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(path(), '/library');
    final tab = tester.widget<AppTabBar>(find.byType(AppTabBar));
    expect(tab.current, 'library');

    await tester.tap(find.byType(IconButtonRound).first);
    await tester.pumpAndSettle();
    expect(path(), '/plan');
    container.dispose();
  });
}
