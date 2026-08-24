import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_open_gym/data/models/app_state.dart';
import 'package:my_open_gym/domain/exercises.dart';
import 'package:my_open_gym/domain/foods.dart';
import 'package:my_open_gym/domain/format.dart';
import 'package:my_open_gym/state/app_state_provider.dart';
import 'package:my_open_gym/ui/app.dart';
import 'package:my_open_gym/ui/screens/stats_screen.dart';
import 'package:my_open_gym/ui/sheets/sheet_service.dart';
import 'package:my_open_gym/ui/widgets/macro_bar.dart';
import 'package:my_open_gym/ui/widgets/media.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
    await Exercises.instance.load();
    await foods.load();
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

  AppState profiled() {
    final s = AppState.defaults();
    s.nutrition.profile
      ..age = 34
      ..height = 178
      ..sex = 'male'
      ..activity = 'light';
    s.bodyweight.add(BodyWeightEntry(d: todayISO(), w: 80));
    return s;
  }

  testWidgets('with no profile the screen asks for one instead of showing dashes',
      (tester) async {
    final container = await pump(tester, null, '/nutrition');
    expect(find.text('Set this up once'), findsOneWidget);
    // Nothing is estimated, so nothing pretends to be.
    expect(find.byType(KcalRing), findsNothing);
    expect(find.byType(MacroBars), findsNothing);
    container.dispose();
  });

  testWidgets('with a weigh-in but no profile it asks for the profile', (tester) async {
    final s = AppState.defaults();
    s.bodyweight.add(BodyWeightEntry(d: todayISO(), w: 80));
    final container = await pump(tester, s, '/nutrition');
    expect(find.text('About you'), findsWidgets);
    container.dispose();
  });

  testWidgets('with no weigh-in it asks to weigh in first', (tester) async {
    final s = AppState.defaults();
    s.nutrition.profile
      ..age = 34
      ..height = 178
      ..sex = 'male';
    final container = await pump(tester, s, '/nutrition');
    expect(find.text('Weigh in'), findsOneWidget);
    container.dispose();
  });

  testWidgets('a complete profile gets a target, a week strip and meal slots', (tester) async {
    final container = await pump(tester, profiled(), '/nutrition');

    expect(find.byType(KcalRing), findsOneWidget);
    expect(find.byType(MacroBars), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Meals'), findsOneWidget);
    // The default split is four meals.
    expect(find.text('Breakfast'), findsOneWidget);
    expect(find.text('Lunch'), findsOneWidget);
    expect(find.text('Snack'), findsOneWidget);
    expect(find.text('Dinner'), findsOneWidget);
    container.dispose();
  });

  testWidgets('a logged meal shows up against its slot', (tester) async {
    final s = profiled();
    s.meals.add(Meal(
      id: 'm1',
      d: todayISO(),
      slot: 0,
      items: [MealItem(fid: 'f0010', g: 200, kcal: 240, p: 45, c: 0, f: 5.2)],
    ));
    final container = await pump(tester, s, '/nutrition');

    expect(find.textContaining('Chicken breast'), findsWidgets);
    expect(find.byType(MacroSplit), findsWidgets);
    container.dispose();
  });

  testWidgets('the tab bar keeps Home lit rather than lighting nothing', (tester) async {
    // /nutrition is not a tab; _isOn maps it onto Home the way /settings already is.
    final container = await pump(tester, profiled(), '/nutrition');
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Nutrition'), findsWidgets);
    container.dispose();
  });

  testWidgets('the food library lists foods and sorts by protein density', (tester) async {
    final container = await pump(tester, profiled(), '/nutrition/foods');

    expect(find.byType(FoodThumb), findsWidgets);
    expect(find.text('Protein / kcal'), findsOneWidget);
    // Egg white is near-pure protein, so the density sort puts it on the first page.
    expect(find.textContaining('Egg white'), findsWidgets);
    container.dispose();
  });

  testWidgets('a food with no photograph falls back to its category glyph', (tester) async {
    // assets/food/ is git-ignored, so this is the normal case in a fresh checkout, not an edge.
    final container = await pump(tester, profiled(), '/nutrition/foods');
    expect(tester.takeException(), isNull);
    expect(find.byType(FoodThumb), findsWidgets);
    container.dispose();
  });

  testWidgets('Home carries a nutrition card only once there is a profile', (tester) async {
    var container = await pump(tester, AppState.defaults(), '/home');
    expect(find.byType(MacroBars), findsNothing);
    container.dispose();

    container = await pump(tester, profiled(), '/home');
    expect(find.text("Today's food"), findsOneWidget);
    expect(find.byType(MacroBars), findsOneWidget);
    container.dispose();
  });

  testWidgets('Stats shows the nutrition card only once meals exist', (tester) async {
    var container = await pump(tester, profiled(), '/stats');
    expect(find.byType(NutritionCard, skipOffstage: false), findsNothing);
    container.dispose();

    final s = profiled();
    s.meals.add(Meal(
      id: 'm1',
      d: todayISO(),
      items: [MealItem(g: 200, kcal: 500, p: 40, c: 40, f: 15)],
    ));
    container = await pump(tester, s, '/stats');
    // Built but below the fold — presence in the tree is the claim, not pixel position.
    expect(find.byType(NutritionCard, skipOffstage: false), findsOneWidget);
    expect(find.byType(MacroLegend, skipOffstage: false), findsWidgets);
    container.dispose();
  });

  testWidgets('Settings offers the nutrition rows', (tester) async {
    final container = await pump(tester, profiled(), '/settings');
    expect(find.text('Food & meals', skipOffstage: false), findsOneWidget);
    expect(find.text('Goal', skipOffstage: false), findsWidgets);
    expect(find.text('Nutrition', skipOffstage: false), findsWidgets);
    container.dispose();
  });

  testWidgets('every new screen paints in both themes', (tester) async {
    for (final theme in ['dark', 'light']) {
      for (final route in ['/nutrition', '/nutrition/foods']) {
        final s = profiled()..theme = theme;
        final container = await pump(tester, s, route);
        expect(tester.takeException(), isNull, reason: '$route in $theme');
        container.dispose();
      }
    }
  });
}
