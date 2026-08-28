import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_open_gym/data/ai/ai_key_store.dart';
import 'package:my_open_gym/data/models/app_state.dart';
import 'package:my_open_gym/domain/exercises.dart';
import 'package:my_open_gym/domain/foods.dart';
import 'package:my_open_gym/domain/format.dart';
import 'package:my_open_gym/state/ai_provider.dart';
import 'package:my_open_gym/state/app_state_provider.dart';
import 'package:my_open_gym/ui/app.dart';
import 'package:my_open_gym/ui/screens/stats_screen.dart';
import 'package:my_open_gym/ui/sheets/sheet_service.dart';
import 'package:flutter/widgets.dart';
import 'package:my_open_gym/ui/widgets/app_icon.dart';
import 'package:my_open_gym/ui/widgets/controls/app_button.dart';
import 'package:my_open_gym/ui/widgets/controls/fields.dart';
import 'package:my_open_gym/ui/widgets/controls/stepper.dart';
import 'package:my_open_gym/ui/widgets/controls/surfaces.dart';
import 'package:my_open_gym/ui/widgets/macro_bar.dart';
import 'package:my_open_gym/ui/widgets/tab_bar.dart';
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

  /// The plan row sits at the bottom of the page, so it has to be scrolled to before it can
  /// be tapped.
  Future<void> openPlan(WidgetTester tester) async {
    final row = find.text('Plan my day', skipOffstage: false);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
  }

  /// Scrolls to whatever the finder points at before tapping it.
  ///
  /// The test viewport is 800x600 and every one of these sheets is taller than that, so a bare
  /// `tap` lands on empty space and silently does nothing — which is exactly how a broken Save
  /// button once passed as a working one.
  Future<void> press(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// The food picker's row for [name], reached the way a person reaches it — by searching.
  ///
  /// Not `find.textContaining(name)` on its own any more. The picker hands its list a bounded
  /// height, so the list is lazy: a food two hundred rows down the catalogue is not built until
  /// something scrolls to it, and a finder cannot scroll to a widget that does not exist.
  /// Typing the name is both what the user does and the only way to reach a food that does not
  /// depend on where the list happens to be sitting.
  /// Returns the row, not the label inside it: once the name has been typed, the search field
  /// itself contains that text and comes first in the tree, so a bare `textContaining` hands
  /// back the field and tapping it merely puts the cursor in it.
  Future<Finder> findFood(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(SearchField).first, name);
    await tester.pumpAndSettle();
    final food = find
        .ancestor(of: find.textContaining(name), matching: find.byType(ListItem))
        .first;
    await tester.ensureVisible(food);
    await tester.pumpAndSettle();
    return food;
  }

  /// The `+` half of a stepper. It is an icon button, not a text `+`, so it cannot be found by
  /// its label the way most controls in this suite can.
  Finder plusIn(Finder stepper) => find.descendant(
        of: stepper,
        matching: find.byWidgetPredicate((w) => w is AppIcon && w.name == 'plus'),
      );

  /// The portion-count stepper in the food detail sheet, scoped to its own row.
  ///
  /// Not `find.byType(AppStepper).first`: the recipe sheet underneath has a "Makes" stepper of
  /// its own that comes first in the tree, so the bare finder reaches through the sheet on top
  /// and taps a control the user cannot even see.
  Finder countStepper() => find.descendant(
        of: find.ancestor(of: find.text('How many'), matching: find.byType(AppRow)),
        matching: find.byType(AppStepper),
      );

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

  testWidgets('Nutrition is a tab, and its children keep it lit', (tester) async {
    // It used to borrow Home's tab, because there was no tab of its own to light. There is now,
    // and `current` is only the first path segment — so the two child screens light it too
    // rather than dropping the bar back to nothing selected.
    for (final path in ['/nutrition', '/nutrition/foods', '/nutrition/recipes']) {
      final container = await pump(tester, profiled(), path);
      final tab = tester.widget<AppTabBar>(find.byType(AppTabBar));
      expect(tab.current, 'nutrition', reason: path);
      expect(find.text('Nutrition'), findsWidgets, reason: path);
      container.dispose();
    }
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

  testWidgets('the nutrition screen owns its own setup rows', (tester) async {
    // These used to live in a Nutrition section on Settings. Nutrition is a tab now and that
    // section is gone, so the screen has to carry both of them itself — otherwise the profile
    // and the goal become things you can only change from a sheet you have to know about.
    final container = await pump(tester, profiled(), '/nutrition');
    expect(find.text('About you', skipOffstage: false), findsWidgets);
    expect(find.text('Goal', skipOffstage: false), findsWidgets);
    // The goal reads as the same summary line Settings used to show.
    expect(find.text('Maintain', skipOffstage: false), findsWidgets);
    container.dispose();
  });

  testWidgets('Settings no longer carries a nutrition section', (tester) async {
    final container = await pump(tester, profiled(), '/settings');
    expect(find.text('Food & meals', skipOffstage: false), findsNothing);
    expect(find.text('About you', skipOffstage: false), findsNothing);
    // 'Nutrition' itself is not asserted absent: the tab bar spells it out on every screen.
    container.dispose();
  });

  group('round two', () {
    testWidgets('the focus card asks for one thing, and it is logging first',
        (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      // A profile with no history cannot be told anything about protein yet.
      expect(find.text('Log what you eat'), findsOneWidget);
      expect(find.text('Get your protein in'), findsNothing);
      container.dispose();
    });

    testWidgets('the day and week lenses both paint', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      expect(find.text('Day'), findsOneWidget);
      expect(find.text('Week'), findsOneWidget);

      await tester.tap(find.text('Week'));
      await tester.pumpAndSettle();
      expect(find.text('Budget'), findsOneWidget);
      expect(tester.takeException(), isNull);
      container.dispose();
    });

    testWidgets('an empty slot offers saved meals; a full one does not', (tester) async {
      final s = profiled();
      s.nutrition.templates.add(MealTemplate(
        id: 'mt1',
        n: 'Usual breakfast',
        items: [MealItem(fid: 'f0010', g: 200, kcal: 240, p: 45, c: 0, f: 5)],
      ));
      final container = await pump(tester, s, '/nutrition');
      expect(find.textContaining('Usual breakfast'), findsWidgets);
      container.dispose();
    });

    testWidgets('recipes can be written down, edited and thrown away', (tester) async {
      // The storage for saved meals existed from the start, but nothing could reach it: a
      // recipe could only come into being by logging the identical meal three times, and once
      // saved it could never be renamed, corrected or deleted. This is the whole round trip.
      final container = await pump(tester, profiled(), '/nutrition/recipes');
      expect(find.text('No recipes yet'), findsOneWidget);

      await press(tester, find.text('New recipe'));
      await tester.enterText(find.byType(AppTextField).first, 'Sandwich and coffee');
      await tester.pumpAndSettle();

      // One ingredient, chosen through the same picker the food log uses.
      await press(tester, find.text('Add ingredient').last);
      await tester.enterText(find.byType(SearchField).first, 'White bread');
      await tester.pumpAndSettle();
      await press(tester, find.text('White bread').last);
      await press(tester, find.text('Add').last);

      await press(tester, find.text('Save'));
      expect(container.read(appStateProvider).nutrition.templates, hasLength(1));
      expect(container.read(appStateProvider).nutrition.templates.first.n, 'Sandwich and coffee');
      expect(find.text('Sandwich and coffee'), findsWidgets);

      // Reopening it edits in place rather than making a second one.
      await press(tester, find.text('Sandwich and coffee').first);
      // Not 'Breakfast': the slot filter chips carry those four words, and a rename onto one of
      // them makes `find.text` ambiguous rather than making the test fail for a real reason.
      await tester.enterText(find.byType(AppTextField).first, 'Toast and coffee');
      await tester.pumpAndSettle();
      await press(tester, find.text('Save'));
      expect(container.read(appStateProvider).nutrition.templates, hasLength(1));
      expect(container.read(appStateProvider).nutrition.templates.first.n, 'Toast and coffee');

      await press(tester, find.text('Toast and coffee').first);
      await press(tester, find.text('Delete'));
      expect(container.read(appStateProvider).nutrition.templates, isEmpty);
      expect(tester.takeException(), isNull);
      container.dispose();
    });

    testWidgets('an ingredient already in the recipe can have its quantity changed',
        (tester) async {
      // Before this, the only way to use more or less of something already on the list was to
      // remove it and search for the same food again — annoying enough on the first ingredient,
      // and worse on the fifth. Tapping the row now reopens the same sheet it was added through,
      // seeded with what is already there, and replaces the entry rather than appending a second
      // one.
      final container = await pump(tester, profiled(), '/nutrition/recipes');
      await press(tester, find.text('New recipe'));
      await tester.enterText(find.byType(AppTextField).first, 'Toast');
      await tester.pumpAndSettle();

      await press(tester, find.text('Add ingredient').last);
      await tester.enterText(find.byType(SearchField).first, 'White bread');
      await tester.pumpAndSettle();
      await press(tester, find.text('White bread').last);
      await press(tester, find.text('Add').last);

      expect(find.textContaining('White bread · 100 g'), findsOneWidget);

      // Tapping the row, not the remove glyph next to it.
      await press(tester, find.textContaining('White bread · 100 g'));

      // The button reads differently here than it does when adding something new — this sheet is
      // changing an amount already on the list, not adding another line to it.
      expect(find.text('Add'), findsNothing);
      final grams = find.byType(NumberBox).first;
      expect(tester.widget<NumberBox>(grams).value, 100);

      await tester.enterText(grams, '250');
      await tester.pumpAndSettle();
      await press(tester, find.text('Save').last);

      // One row, not two — this changed the ingredient rather than adding a second one beside it.
      expect(find.textContaining('White bread'), findsOneWidget);
      expect(find.textContaining('White bread · 250 g'), findsOneWidget);

      await press(tester, find.text('Save').last);
      final saved = container.read(appStateProvider).nutrition.templates.single;
      expect(saved.items, hasLength(1));
      expect(saved.items.single.g, 250);
      container.dispose();
    });

    testWidgets('an ingredient can be added as a count of household measures',
        (tester) async {
      // Scrambled eggs is three eggs, one ingredient. Before this the picker only offered "1
      // large", so three of them meant searching for the same food three times and ending up
      // with three identical rows the recipe then had to add together.
      //
      // "Egg, whole" carries USDA measures: small 38 g, medium 44 g, large 50 g, extra large
      // 56 g, at 143 kcal / 100 g.
      final container = await pump(tester, profiled(), '/nutrition/recipes');
      await press(tester, find.text('New recipe'));
      await tester.enterText(find.byType(AppTextField).first, 'Scrambled eggs');
      await tester.pumpAndSettle();

      await press(tester, find.text('Add ingredient').last);
      await tester.enterText(find.byType(SearchField).first, 'Egg, whole');
      await tester.pumpAndSettle();
      await press(tester, find.text('Egg, whole').last);

      // No count until a measure is picked: a free-grams portion has nothing to multiply.
      expect(find.text('How many'), findsNothing);
      await press(tester, find.text('large'));
      expect(find.text('How many'), findsOneWidget);

      final count = countStepper();
      expect(tester.widget<AppStepper>(count).value, 1);
      expect(tester.widget<NumberBox>(find.byType(NumberBox).first).value, 50);

      // Twice up the stepper: three large eggs.
      await press(tester, plusIn(count));
      await press(tester, plusIn(count));
      expect(tester.widget<AppStepper>(count).value, 3);
      expect(tester.widget<NumberBox>(find.byType(NumberBox).first).value, 150);

      await press(tester, find.text('Add').last);
      await press(tester, find.text('Save').last);

      // One ingredient at three eggs' worth, not three ingredients — and the macros are the
      // catalogue's, scaled by the grams the count worked out to.
      final saved = container.read(appStateProvider).nutrition.templates.single;
      expect(saved.items, hasLength(1));
      expect(saved.items.single.g, 150);
      expect(saved.items.single.kcal, closeTo(143 * 1.5, 0.01));
      container.dispose();
    });

    testWidgets('reopening a counted ingredient shows the count again', (tester) async {
      // Only the weight is stored, so the count is recovered by seeing which measure divides it
      // evenly. Without that, editing "3 large" would come back as a bare 150 g and the user
      // would be back to doing the arithmetic the count exists to avoid.
      final container = await pump(tester, profiled(), '/nutrition/recipes');
      await press(tester, find.text('New recipe'));
      await tester.enterText(find.byType(AppTextField).first, 'Scrambled eggs');
      await tester.pumpAndSettle();

      await press(tester, find.text('Add ingredient').last);
      await tester.enterText(find.byType(SearchField).first, 'Egg, whole');
      await tester.pumpAndSettle();
      await press(tester, find.text('Egg, whole').last);
      await press(tester, find.text('large'));
      final count = countStepper();
      await press(tester, plusIn(count));
      await press(tester, find.text('Add').last);

      // One press of `+`: two large eggs, so 100 g.
      expect(find.textContaining('100 g'), findsOneWidget);
      await press(tester, find.textContaining('100 g'));

      expect(find.text('How many'), findsOneWidget);
      expect(tester.widget<AppStepper>(countStepper()).value, 2);
      expect(find.text('large'), findsWidgets, reason: 'the measure came back too, not just 100 g');
      container.dispose();
    });

    testWidgets('typing a weight drops the count rather than contradicting it',
        (tester) async {
      // Grams stay the source of truth. A count left on screen beside a weight it no longer
      // multiplies out to is the screen asserting two different things at once.
      final container = await pump(tester, profiled(), '/nutrition/recipes');
      await press(tester, find.text('New recipe'));
      await tester.enterText(find.byType(AppTextField).first, 'Scrambled eggs');
      await tester.pumpAndSettle();

      await press(tester, find.text('Add ingredient').last);
      await tester.enterText(find.byType(SearchField).first, 'Egg, whole');
      await tester.pumpAndSettle();
      await press(tester, find.text('Egg, whole').last);
      await press(tester, find.text('large'));
      expect(find.text('How many'), findsOneWidget);

      await tester.enterText(find.byType(NumberBox).first, '90');
      await tester.pumpAndSettle();

      expect(find.text('How many'), findsNothing);
      await press(tester, find.text('Add').last);
      await press(tester, find.text('Save').last);
      expect(container.read(appStateProvider).nutrition.templates.single.items.single.g, 90);
      container.dispose();
    });

    testWidgets('a recipe reaches the nutrition screen as somewhere to go', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      expect(find.text('Recipes', skipOffstage: false), findsOneWidget);
      container.dispose();
    });

    testWidgets('the plan and copy-a-day rows are offered', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      expect(find.text('Plan my day', skipOffstage: false), findsOneWidget);
      expect(find.text('Copy a day', skipOffstage: false), findsOneWidget);
      container.dispose();
    });

    testWidgets('generating a plan logs nothing on its own', (tester) async {
      // The property Phase 6 is built around, asserted through the real widget tree rather
      // than only in the domain test.
      final container = await pump(tester, profiled(), '/nutrition');
      await openPlan(tester);

      expect(find.text('A day that fits'), findsOneWidget);
      expect(find.text('Log this meal'), findsWidgets);
      expect(container.read(appStateProvider).meals, isEmpty);
      container.dispose();
    });

    testWidgets('a planned meal only lands in the log when it is tapped', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await openPlan(tester);

      await press(tester, find.text('Log this meal').first);

      final meals = container.read(appStateProvider).meals;
      expect(meals, hasLength(1));
      expect(meals.single.items, isNotEmpty);
      container.dispose();
    });

    testWidgets('the breakdown opens and shows its arithmetic', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await tester.tap(find.text('Target'));
      await tester.pumpAndSettle();

      expect(find.text('How this was worked out'), findsOneWidget);
      expect(find.text('Resting'), findsOneWidget);
      expect(find.text('Maintenance'), findsOneWidget);
      container.dispose();
    });

    testWidgets('no adjustment is offered without the evidence for one', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      expect(find.text('Your target may be off'), findsNothing);
      container.dispose();
    });
  });

  /// Every sheet in the feature, opened and painted.
  ///
  /// This group exists because it did not, and a Segmented control placed in a list row's
  /// trailing slot shipped with no width. AppRow lays that slot out in an unbounded Row and
  /// Segmented divides its width with Expanded, so the first person to open the goal sheet got
  /// a layout assertion and a broken screen. Nothing else in the suite ever opened these.
  group('every sheet opens', () {
    Future<void> openFrom(WidgetTester tester, String label) async {
      final row = find.text(label, skipOffstage: false);
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      await tester.tap(row);
      await tester.pumpAndSettle();
    }

    testWidgets('the body profile sheet', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await openFrom(tester, 'About you');
      expect(tester.takeException(), isNull);
      // The control that broke: two options sharing a fixed width in a list row.
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      container.dispose();
    });

    testWidgets('the goal sheet, including the meals stepper', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      // Reached from the gear in the header rather than a row.
      await tester.tap(find.byType(IconButtonRound).first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Your goal'), findsOneWidget);
      expect(find.text('Meals per day'), findsOneWidget);
      expect(find.text('Lose'), findsOneWidget);
      container.dispose();
    });

    testWidgets('the goal sheet survives switching mode and stepping meals', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await tester.tap(find.byType(IconButtonRound).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lose'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The rate row only exists once the goal is not "maintain".
      expect(find.text('Kilos per week'), findsOneWidget);

      // `.last`, not a bare finder: the screen underneath now summarises the same goal in its
      // own row, so 'Maintain' matches twice. The sheet is a route pushed over the screen, so
      // it is the later of the two in the tree — which is the one a finger would reach.
      await tester.tap(find.text('Maintain').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      container.dispose();
    });

    testWidgets('the food picker, and the detail sheet under it', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await openFrom(tester, 'Breakfast');
      expect(tester.takeException(), isNull);
      expect(find.text('Search foods'), findsOneWidget);

      final food = await findFood(tester, 'Chicken breast');
      await tester.tap(food);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Portion chips come from the food's own household measures — chicken has "piece". The
      // count that multiplies it lives in its own row and only appears once one is picked, so
      // the chip is the bare measure rather than "1 piece".
      expect(find.text('Grams'), findsOneWidget);
      expect(find.textContaining('piece'), findsWidgets);
      expect(find.text('How many'), findsNothing);
      container.dispose();
    });

    testWidgets('the copy-a-day sheet with nothing to copy', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await openFrom(tester, 'Copy a day');
      expect(tester.takeException(), isNull);
      expect(find.text('Nothing to copy yet'), findsOneWidget);
      container.dispose();
    });

    testWidgets('the breakdown sheet', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await tester.tap(find.text('Target'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      container.dispose();
    });

    testWidgets('the day plan sheet', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await openPlan(tester);
      expect(tester.takeException(), isNull);
      container.dispose();
    });

    // One test per theme rather than a loop in one test: a sheet left open by the first pass
    // is still mounted when the second pumps over it, and the finder then matches the old
    // screen as well as the new one.
    for (final theme in ['dark', 'light']) {
      testWidgets('the profile sheet lays out in $theme', (tester) async {
        final container = await pump(tester, profiled()..theme = theme, '/nutrition');
        await openFrom(tester, 'About you');
        expect(tester.takeException(), isNull, reason: theme);
        expect(find.text('Male'), findsOneWidget, reason: theme);
        container.dispose();
      });
    }
  });

  /// Typing into things.
  ///
  /// The gap that shipped a broken profile sheet twice over: the sheet tests opened each sheet
  /// and asserted it did not throw, which a screen full of untappable text passes perfectly
  /// well. A field is not working until something has been entered into it and come back out.
  group('the fields accept input', () {
    Future<void> openProfile(WidgetTester tester) async =>
        press(tester, find.text('About you', skipOffstage: false));

    testWidgets('age and height can be typed and saved', (tester) async {
      // Start from a profile with no body metrics at all, the state a new user is in.
      final s = AppState.defaults();
      s.bodyweight.add(BodyWeightEntry(d: todayISO(), w: 80));
      final container = await pump(tester, s, '/nutrition');
      await openProfile(tester);

      final fields = find.byType(NumberBox);
      expect(fields, findsNWidgets(2), reason: 'age and height');

      await tester.enterText(fields.at(0), '41');
      await tester.pumpAndSettle();
      await tester.enterText(fields.at(1), '183');
      await tester.pumpAndSettle();

      await press(tester, find.text('Save'));

      final p = container.read(appStateProvider).nutrition.profile;
      expect(p.age, 41);
      expect(p.height, 183);
      expect(p.isComplete, isTrue);
      container.dispose();
    });

    testWidgets('tapping a field focuses it', (tester) async {
      // The actual defect: NumberField is a bare EditableText with no gesture handling, so a
      // tap did nothing at all. Focus after a tap is the property that was missing.
      final container = await pump(tester, profiled(), '/nutrition');
      await openProfile(tester);

      final box = find.byType(NumberBox).first;
      final field = find.descendant(of: box, matching: find.byType(EditableText));
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);

      await tester.tap(box);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);
      container.dispose();
    });

    testWidgets('an exaggerated age cannot be typed in the first place', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await openProfile(tester);

      await tester.enterText(find.byType(NumberBox).at(0), '999');
      await tester.pumpAndSettle();
      // Held at the ceiling as it is typed rather than accepted and objected to on Save.
      expect(find.text('100'), findsOneWidget);

      await press(tester, find.text('Save'));
      expect(container.read(appStateProvider).nutrition.profile.age, 100);
      container.dispose();
    });

    testWidgets('an absurd height is capped as it is typed', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await openProfile(tester);

      await tester.enterText(find.byType(NumberBox).at(1), '9999');
      await tester.pumpAndSettle();
      expect(find.text('230'), findsOneWidget);

      await press(tester, find.text('Save'));
      expect(container.read(appStateProvider).nutrition.profile.height, 230);
      container.dispose();
    });

    testWidgets('a value inside the range is left exactly alone', (tester) async {
      // The clamp must not round or nudge anything it has no business touching.
      final container = await pump(tester, profiled(), '/nutrition');
      await openProfile(tester);

      await tester.enterText(find.byType(NumberBox).at(0), '99');
      await tester.enterText(find.byType(NumberBox).at(1), '229');
      await tester.pumpAndSettle();
      await press(tester, find.text('Save'));

      final p = container.read(appStateProvider).nutrition.profile;
      expect(p.age, 99);
      expect(p.height, 229);
      container.dispose();
    });

    testWidgets('an out-of-range age is refused, and says why', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await openProfile(tester);

      await tester.enterText(find.byType(NumberBox).at(0), '7');
      await tester.pumpAndSettle();
      await press(tester, find.text('Save'));

      // The sheet stays open, the message names the range, and nothing was written.
      expect(find.text('Between 13 and 100'), findsOneWidget);
      expect(container.read(appStateProvider).nutrition.profile.age, 34);
      container.dispose();
    });

    testWidgets('a height typed in metres is caught and explained', (tester) async {
      // The mistake people actually make: 1.78 rather than 178.
      final container = await pump(tester, profiled(), '/nutrition');
      await openProfile(tester);

      await tester.enterText(find.byType(NumberBox).at(1), '1.78');
      await tester.pumpAndSettle();
      await press(tester, find.text('Save'));

      expect(find.text('In centimetres — 178, not 1.78'), findsOneWidget);
      expect(container.read(appStateProvider).nutrition.profile.height, 178);
      container.dispose();
    });

    testWidgets('an empty field is asked for rather than silently rejected', (tester) async {
      final s = AppState.defaults();
      s.bodyweight.add(BodyWeightEntry(d: todayISO(), w: 80));
      final container = await pump(tester, s, '/nutrition');
      await openProfile(tester);

      await press(tester, find.text('Save'));

      expect(find.text('How old are you?'), findsOneWidget);
      expect(find.text('How tall are you?'), findsOneWidget);
      container.dispose();
    });

    testWidgets('nothing is shouted at before Save is pressed', (tester) async {
      // A half-typed number on the way to a good one must not turn the field red.
      final s = AppState.defaults();
      s.bodyweight.add(BodyWeightEntry(d: todayISO(), w: 80));
      final container = await pump(tester, s, '/nutrition');
      await openProfile(tester);

      expect(find.text('How old are you?'), findsNothing);
      await tester.enterText(find.byType(NumberBox).at(0), '1');
      await tester.pumpAndSettle();
      expect(find.text('Between 13 and 100'), findsNothing);
      container.dispose();
    });

    testWidgets('fixing the value clears the message', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await openProfile(tester);

      await tester.enterText(find.byType(NumberBox).at(0), '7');
      await tester.pumpAndSettle();
      await press(tester, find.text('Save'));
      expect(find.text('Between 13 and 100'), findsOneWidget);

      await tester.enterText(find.byType(NumberBox).at(0), '41');
      await tester.pumpAndSettle();
      expect(find.text('Between 13 and 100'), findsNothing);

      await press(tester, find.text('Save'));
      expect(container.read(appStateProvider).nutrition.profile.age, 41);
      container.dispose();
    });

    testWidgets('a portion can be typed and it moves the totals', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      final slot = find.text('Breakfast', skipOffstage: false);
      await tester.ensureVisible(slot);
      await tester.pumpAndSettle();
      await tester.tap(slot);
      await tester.pumpAndSettle();

      final food = await findFood(tester, 'Chicken breast');
      await tester.tap(food);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(NumberBox).first, '250');
      await tester.pumpAndSettle();

      final add = find.text('Add to the day');
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();

      final meals = container.read(appStateProvider).meals;
      expect(meals, hasLength(1));
      expect(meals.single.items.single.g, 250);
      container.dispose();
    });

    testWidgets('quick add takes a bare calorie count', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      final slot = find.text('Lunch', skipOffstage: false);
      await tester.ensureVisible(slot);
      await tester.pumpAndSettle();
      await tester.tap(slot);
      await tester.pumpAndSettle();

      await press(tester, find.text('Quick add'));

      await tester.enterText(find.byType(NumberBox).at(0), '640');
      await tester.pumpAndSettle();
      final add = find.widgetWithText(AppButton, 'Add');
      await tester.ensureVisible(add);
      await tester.pumpAndSettle();
      await tester.tap(add);
      await tester.pumpAndSettle();

      final meals = container.read(appStateProvider).meals;
      expect(meals, hasLength(1));
      expect(meals.single.items.single.kcal, 640);
      // No food behind it, so no weight is invented.
      expect(meals.single.items.single.g, 0);
      container.dispose();
    });

    testWidgets('the goal rate can be typed', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await press(tester, find.byType(IconButtonRound).first);

      await press(tester, find.text('Lose'));
      await tester.enterText(find.byType(NumberBox).first, '0.75');
      await tester.pumpAndSettle();
      final save = find.text('Save goal');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(container.read(appStateProvider).nutrition.goal.rate, -0.75);
      container.dispose();
    });
  });

  /// Getting back out of a sheet.
  ///
  /// Dragging one down always worked; nothing on screen ever said so, and a sheet opened from
  /// another sheet had no way to say "this goes back, not out". Following a swap suggestion put
  /// you three deep with no visible exit.
  group('sheets can be left', () {
    /// The sheet's own way out, found by its glyph.
    /// The sheet's own chrome. Scoped to [IconButtonRound] because that is what the shell puts
    /// its close and back controls in, and other things on screen draw the same glyphs — a
    /// search field with text in it grows an xmark of its own to clear itself with.
    Finder controlIcon(String name) => find.descendant(
          of: find.byType(IconButtonRound),
          matching: find.byWidgetPredicate((w) => w is AppIcon && w.name == name),
        );

    testWidgets('a sheet opened from a screen offers a close', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await press(tester, find.text('About you', skipOffstage: false));

      expect(find.text('About you'), findsWidgets);
      expect(controlIcon('xmark'), findsOneWidget);
      expect(controlIcon('chevronLeft'), findsNothing);
      container.dispose();
    });

    testWidgets('and closing it returns to the screen', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await press(tester, find.text('About you', skipOffstage: false));
      expect(find.byType(NumberBox), findsWidgets);

      await press(tester, controlIcon('xmark'));
      expect(find.byType(NumberBox), findsNothing);
      container.dispose();
    });

    testWidgets('a sheet opened from a sheet offers a back arrow instead', (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await press(tester, find.text('Breakfast', skipOffstage: false));
      expect(controlIcon('xmark'), findsOneWidget, reason: 'the picker is the first sheet');

      final food = await findFood(tester, 'Chicken breast');
      await press(tester, food);

      // Now two deep: leaving goes back to the picker, which is a different promise.
      expect(controlIcon('chevronLeft'), findsOneWidget);
      container.dispose();
    });

    testWidgets('going back lands on the sheet underneath, not on the screen',
        (tester) async {
      final container = await pump(tester, profiled(), '/nutrition');
      await press(tester, find.text('Breakfast', skipOffstage: false));

      final food = await findFood(tester, 'Chicken breast');
      await press(tester, food);
      expect(find.text('Portion'), findsOneWidget);

      await press(tester, controlIcon('chevronLeft'));
      // Back on the picker, not out of both.
      expect(find.text('Search foods'), findsOneWidget);
      expect(find.text('Portion'), findsNothing);
      container.dispose();
    });

    testWidgets('the depth resets, so the next sheet is a close again', (tester) async {
      // The counter is the thing most likely to leak: open, nest, back out fully, open again.
      final container = await pump(tester, profiled(), '/nutrition');
      await press(tester, find.text('Breakfast', skipOffstage: false));
      final food = await findFood(tester, 'Chicken breast');
      await press(tester, food);
      await press(tester, controlIcon('chevronLeft'));
      await press(tester, controlIcon('xmark'));

      await press(tester, find.text('About you', skipOffstage: false));
      expect(controlIcon('xmark'), findsOneWidget);
      expect(controlIcon('chevronLeft'), findsNothing);
      container.dispose();
    });
  });

  /// Everything, on a small phone.
  ///
  /// The default test viewport is 800x600 — wider than any phone this ships to, which is how a
  /// tag row that overflows at 360 px passed every other test in this file.
  group('at phone width', () {
    /// Pumps at 360x780 — a common Android phone — and hands back a tree with the *known*
    /// pre-existing Home overflow already drained.
    ///
    /// HomeScreen's today row needs 393 px and overflows by 33 on a 360 dp screen. That is not
    /// this feature's bug: it reproduces with an empty profile, where none of the nutrition
    /// cards render at all. It is drained here so these tests can still say something true
    /// about the surfaces they do own, and it should be fixed on its own terms.
    Future<ProviderContainer> pumpNarrow(WidgetTester tester, AppState s, String route,
        {ProviderContainer? container}) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final c = container ?? ProviderContainer();
      c.read(appStateProvider.notifier).replaceState(s);
      await tester.pumpWidget(
          UncontrolledProviderScope(container: c, child: const MyOpenGymApp()));
      await tester.pumpAndSettle();
      while (tester.takeException() != null) {}

      appNavigatorKey.currentContext!.go(route);
      await tester.pumpAndSettle();
      return c;
    }

    testWidgets('the nutrition screen fits', (tester) async {
      final container = await pumpNarrow(tester, profiled(), '/nutrition');
      expect(tester.takeException(), isNull);
      container.dispose();
    });

    testWidgets('the food library fits', (tester) async {
      final container = await pumpNarrow(tester, profiled(), '/nutrition/foods');
      expect(tester.takeException(), isNull);
      container.dispose();
    });

    testWidgets('the food detail sheet fits', (tester) async {
      // The one that actually overflowed: a category tag and "g protein / 100 kcal" side by
      // side are wider than 360 px.
      final container = await pumpNarrow(tester, profiled(), '/nutrition');
      await press(tester, find.text('Breakfast', skipOffstage: false));
      final food = await findFood(tester, 'Chicken breast');
      await press(tester, food);
      expect(tester.takeException(), isNull);
      container.dispose();
    });

    testWidgets('the profile and goal sheets fit', (tester) async {
      var container = await pumpNarrow(tester, profiled(), '/nutrition');
      await press(tester, find.text('About you', skipOffstage: false));
      expect(tester.takeException(), isNull, reason: 'profile');
      container.dispose();

      container = await pumpNarrow(tester, profiled(), '/nutrition');
      await press(tester, find.byType(IconButtonRound).first);
      expect(tester.takeException(), isNull, reason: 'goal');
      container.dispose();
    });

    testWidgets('the day plan fits', (tester) async {
      final container = await pumpNarrow(tester, profiled(), '/nutrition');
      await openPlan(tester);
      expect(tester.takeException(), isNull);
      container.dispose();
    });

    testWidgets('the food picker keeps its buttons on the screen', (tester) async {
      // The bug this was written for: the picker's list had no bounded height to take a share
      // of, so it grew to all 240-odd foods and carried everything below it — Quick add, Your
      // own food — off the bottom of the phone. Nothing overflowed and nothing threw; the
      // buttons were simply somewhere no finger could reach, and the list ate the drag that
      // would have brought them back.
      //
      // Asserted on geometry rather than on the finder, because `find` is perfectly happy with
      // a widget laid out past the bottom of the world.
      final container = await pumpNarrow(tester, profiled(), '/nutrition');
      await press(tester, find.text('Breakfast', skipOffstage: false));

      final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
      for (final label in ['Quick add', 'Your own food']) {
        final box = tester.getRect(find.text(label));
        expect(box.bottom, lessThanOrEqualTo(screen), reason: '$label is below the screen');
        expect(box.top, greaterThanOrEqualTo(0), reason: '$label is above the screen');
      }

      // And the list above them still has room to be a list, rather than having been squeezed
      // to nothing by a footer that now always fits.
      expect(find.byType(ListItem), findsWidgets);
      expect(tester.takeException(), isNull);
      container.dispose();
    });

    testWidgets('the food picker still fits with the photo button showing', (tester) async {
      // The scenario the test above never touched: `profiled()` alone never enables the meal
      // photo feature, so "Log from a photo" never renders in it and its extra height was never
      // part of that layout pass. With the feature on, this button sits above Quick add / Your
      // own food, and on a short phone the fixed content — search field, category chips, this
      // button, the two icon tiles — can add up to more than the sheet's own height budget even
      // with the food list capped at nothing. That is a real overflow, not an off-screen button,
      // so this asserts on the exception rather than on geometry.
      final s = profiled();
      s.ai.feature(aiMealPhoto)
        ..on = true
        ..provider = 'anthropic';

      final container = ProviderContainer(
        overrides: [
          aiKeyStoreProvider
              .overrideWithValue(MemoryAiKeyStore(const {'anthropic': 'sk-ant-x'})),
        ],
      );
      await pumpNarrow(tester, s, '/nutrition', container: container);
      await press(tester, find.text('Breakfast', skipOffstage: false));

      // findsWidgets, not findsOneWidget: the sources card behind the sheet carries the same
      // label on its own discovery row.
      expect(find.text('Log from a photo'), findsWidgets);
      expect(tester.takeException(), isNull);
      container.dispose();
    });

    testWidgets('the food picker scrolls', (tester) async {
      // The other half of the same bug. A shrink-wrapped list with nothing to scroll still wins
      // the drag, so the sheet read as frozen — which is how a user finds out the buttons are
      // gone rather than merely off-screen.
      final container = await pumpNarrow(tester, profiled(), '/nutrition');
      await press(tester, find.text('Breakfast', skipOffstage: false));

      final first = find.byType(ListItem).first;
      final before = tester.getRect(first).top;
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pumpAndSettle();

      expect(tester.getRect(first).top, lessThan(before),
          reason: 'dragging the food list did not move it');
      container.dispose();
    });
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
