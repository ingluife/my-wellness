import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/exercises.dart';
import 'package:my_wellness/state/app_state_provider.dart';
import 'package:my_wellness/ui/app.dart';
import 'package:my_wellness/ui/sheets/sheet_service.dart';
import 'package:my_wellness/ui/widgets/tab_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
    await Exercises.instance.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the app boots into Home with the tab bar available', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyWellnessApp()));
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
      UncontrolledProviderScope(container: container, child: const MyWellnessApp()),
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

  /// The round Start disc itself, found by the one thing that is true of it and nothing else in
  /// the bar: it is the circle.
  final disc = find.descendant(
    of: find.byType(AppTabBar),
    matching: find.byWidgetPredicate(
        (w) => w is Container && w.decoration is BoxDecoration
            && (w.decoration as BoxDecoration).shape == BoxShape.circle),
  );

  testWidgets('the docked Start disc is whole, centred, and clear of the bar', (tester) async {
    // The bug this pins: the disc used to be lifted out of the bar's row with a Transform, and
    // the ClipRect that bounds the bar's BackdropFilter sheared the top third of it off — a
    // green half-circle sitting flat against the bar's top edge.
    await tester.pumpWidget(const ProviderScope(child: MyWellnessApp()));
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byType(AppTabBar));
    final surface = tester.getRect(
        find.descendant(of: find.byType(AppTabBar), matching: find.byType(BackdropFilter)));
    final button = tester.getRect(disc);

    expect(button.top, greaterThanOrEqualTo(bar.top),
        reason: 'a disc above the bar widget is a disc nothing will paint or hit-test');
    expect(button.bottom, lessThanOrEqualTo(bar.bottom));
    // Docked, not sunk: it genuinely overhangs the blurred surface rather than sitting inside it.
    expect(button.top, lessThan(surface.top));

    expect(button.center.dx, bar.center.dx, reason: 'centred on the bar, not merely near it');

    // The two labels sit on one line — the reason _lift is derived rather than eyeballed.
    expect(
      tester.getRect(find.text('Start')).center.dy,
      closeTo(tester.getRect(find.text('Home')).center.dy, 1),
    );
  });

  testWidgets('the overhanging top of the disc still takes a tap', (tester) async {
    // The half of the old bug a screenshot could not show. Hit testing is bounded by the box a
    // widget was laid out in, so the part of the disc that hung outside the bar was dead to touch
    // as well as invisible — and that dead strip was the part nearest the thumb.
    await tester.pumpWidget(const ProviderScope(child: MyWellnessApp()));
    await tester.pumpAndSettle();

    await tester.tapAt(tester.getRect(disc).topCenter + const Offset(0, 2));
    await tester.pumpAndSettle();

    // No routine in a default profile, so Start goes to the workout screen rather than into a
    // session — either way, the tap was received.
    expect(find.byType(AppTabBar), findsOneWidget);
    expect(GoRouter.of(appNavigatorKey.currentContext!).state.uri.path, '/workout');
  });

  testWidgets('a running workout turns the Start disc into Resume', (tester) async {
    final container = ProviderContainer();
    container.read(appStateProvider.notifier).replaceState(
          AppState.defaults()
            ..active = ActiveWorkout(id: 'a', d: '2026-08-24', start: 0, name: 'Push Day'),
        );

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MyWellnessApp()),
    );
    await tester.pump();

    // Home's today-row and the tab bar's disc both say Resume once a session is running.
    expect(find.text('Resume'), findsNWidgets(2));
    expect(find.text('Start'), findsNothing);

    container.dispose();
  });
}
