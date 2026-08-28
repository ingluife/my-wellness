import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_open_gym/data/ai/ai_key_store.dart';
import 'package:my_open_gym/data/models/app_state.dart';
import 'package:my_open_gym/data/repositories/meal_photo_store.dart';
import 'package:my_open_gym/domain/ai/ai_provider.dart';
import 'package:my_open_gym/domain/exercises.dart';
import 'package:my_open_gym/domain/foods.dart';
import 'package:my_open_gym/domain/format.dart';
import 'package:my_open_gym/platform/photo_capture.dart';
import 'package:my_open_gym/state/ai_provider.dart';
import 'package:my_open_gym/state/app_state_provider.dart';
import 'package:my_open_gym/ui/app.dart';
import 'package:my_open_gym/ui/sheets/sheet_service.dart';
import 'package:my_open_gym/ui/widgets/app_icon.dart';
import 'package:my_open_gym/ui/widgets/controls/app_button.dart';
import 'package:my_open_gym/ui/widgets/controls/fields.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The photo flow end to end, with a fake camera and a fake provider.
///
/// The provider double returns **canned raw JSON**, not a canned draft, so the real sanitizer
/// runs inside every one of these tests. A fake that handed back a finished `MealDraft` would
/// test the sheet against a world where the model is always well behaved, which is the one world
/// it will never be in.
void main() {
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
  final today = isoOf(DateTime.now());

  /// Real catalogue foods, so `Food.portion` has something to resolve against.
  ///
  /// Assigned in setUpAll, not at the top level: the catalogue loads from the asset bundle, and
  /// anything here that reads `foods.db` directly runs before that has happened.
  late final Food chicken;
  late final Food rice;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
    await Exercises.instance.load();
    await foods.load();
    chicken = foods.db.firstWhere((f) => f.p > 20);
    rice = foods.db.firstWhere((f) => f.cat == 'carb' && f.id != chicken.id);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Stands in for the app documents directory. Fresh per test, so what a test finds in it is
  /// only ever what that test put there.
  late MemoryMealPhotoStore photos;
  setUp(() => photos = MemoryMealPhotoStore());

  Object answer(List<Map<String, dynamic>> items) =>
      jsonDecode(jsonEncode({'confidence': 'high', 'items': items}));

  /// A profile complete enough for the nutrition screen to render its real content.
  ///
  /// Without this the screen shows only its "set this up once" card, and none of the logging
  /// affordances exist to be tested. Mirrors `profiled()` in nutrition_screen_test.dart.
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

  /// A profiled state with the photo feature switched on.
  AppState onState() {
    final s = profiled();
    s.ai.feature(aiMealPhoto)
      ..on = true
      ..provider = 'anthropic'
      ..model = 'claude-opus-5';
    return s;
  }

  /// [result] null leaves `aiMealPhotoProvider` alone, so the real availability logic runs — which
  /// is the only way to test that the entry point disappears when the feature is off.
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    AiResult? result,
    AppState? initial,
    bool cancelPicker = false,
  }) async {
    final container = ProviderContainer(overrides: [
      aiKeyStoreProvider.overrideWithValue(MemoryAiKeyStore(const {'anthropic': 'sk-ant-x'})),
      photoCaptureProvider
          .overrideWithValue(MemoryPhotoCapture(cancelPicker ? null : jpeg)),
      mealPhotoStoreProvider.overrideWithValue(photos),
      if (result != null) aiMealPhotoProvider.overrideWithValue(_FakeVision(result)),
    ]);
    container.read(appStateProvider.notifier).replaceState(initial ?? onState());
    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyOpenGymApp()));
    await tester.pumpAndSettle();
    appNavigatorKey.currentContext!.go('/nutrition');
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> press(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Opens the sheet through the discovery row and takes the photo.
  ///
  /// `skipOffstage: false` because the sources card sits below the fold of a scrolling page and is
  /// not built until scrolled to — the same workaround nutrition_screen_test.dart documents for
  /// its own "Plan my day" row.
  Future<void> shoot(WidgetTester tester) async {
    await press(tester, find.text('Log from a photo', skipOffstage: false).last);
    await press(tester, find.text('Take a photo'));
  }

  testWidgets('the entry point is absent until the feature is on', (tester) async {
    // No provider override here on purpose: the real availability logic is the thing under test.
    final container = await pump(tester, initial: profiled());

    expect(find.text('Log from a photo', skipOffstage: false), findsNothing);
    expect(find.text('Set up meal photos', skipOffstage: false), findsOneWidget);

    // And no camera affordance on any meal slot either.
    final sparkles = find.byWidgetPredicate(
        (w) => w is AppIcon && w.name == 'sparkles' && w.size == 15,
        skipOffstage: false);
    expect(sparkles, findsNothing);
    container.dispose();
  });

  testWidgets('with the feature on, each meal slot offers the camera', (tester) async {
    final container = await pump(tester, result: AiDraft(answer([])));
    final sparkles = find.byWidgetPredicate(
        (w) => w is AppIcon && w.name == 'sparkles' && w.size == 15,
        skipOffstage: false);
    expect(sparkles, findsWidgets);
    container.dispose();
  });

  testWidgets('the food picker offers the camera, and carries the slot with it', (tester) async {
    // Where the user actually is when they want this. Tapping a meal opens the food picker, and
    // before this the only way on from there was a 15px glyph on the card now underneath it —
    // an entry point nobody finds, which is exactly what was reported.
    final container = await pump(
      tester,
      result: AiDraft(answer([
        {'fid': chicken.id, 'name': 'Chicken', 'grams': 100},
      ])),
    );

    await press(tester, find.text('Breakfast', skipOffstage: false));
    expect(find.text('Quick add'), findsOneWidget, reason: 'the picker is up');

    // By type, not by text: the nutrition screen behind this sheet carries the same words on a
    // row, and this test is about the button inside the picker.
    await press(tester, find.widgetWithText(AppButton, 'Log from a photo'));
    // The picker gets out of the way rather than waiting underneath for a meal that is already
    // logged by the time the review sheet closes.
    expect(find.text('Quick add'), findsNothing);

    await press(tester, find.text('Take a photo'));
    await press(tester, find.text('Log this meal'));

    // Slot 0 — breakfast — not the unassigned slot the generic row logs into. A photo button that
    // lost the slot would file every meal it took under "Other".
    expect(container.read(appStateProvider).meals.single.slot, 0);
    container.dispose();
  });

  testWidgets('the picker offers it only when the feature is on', (tester) async {
    // No override, so the real availability logic runs. Absent rather than disabled, like every
    // other affordance this feature owns.
    final container = await pump(tester, initial: profiled());
    await press(tester, find.text('Breakfast', skipOffstage: false));

    expect(find.widgetWithText(AppButton, 'Log from a photo'), findsNothing);
    // ...and the two ordinary ways in are untouched.
    expect(find.text('Quick add'), findsOneWidget);
    container.dispose();
  });

  testWidgets('picking an ingredient for a recipe is not offered a camera', (tester) async {
    // The picker doubles as a chooser for the recipe editor, where a photograph has nothing to
    // log into — there is no day and no slot, only an ingredient being named.
    final container = await pump(tester, result: AiDraft(answer([])));

    appNavigatorKey.currentContext!.go('/nutrition/recipes');
    await tester.pumpAndSettle();
    await press(tester, find.text('New recipe'));
    await press(tester, find.text('Add ingredient').last);

    expect(find.text('Log from a photo'), findsNothing);
    expect(find.text('Quick add'), findsNothing, reason: 'the same rule, already established');
    container.dispose();
  });

  testWidgets('a photo produces a reviewable draft and writes nothing yet', (tester) async {
    final container = await pump(
      tester,
      result: AiDraft(answer([
        {'fid': chicken.id, 'name': 'Chicken', 'grams': 200, 'gramsLow': 150, 'gramsHigh': 260},
        {'fid': rice.id, 'name': 'Rice', 'grams': 180},
      ])),
    );

    await shoot(tester);

    expect(find.text('Check what you ate'), findsOneWidget);
    // The catalogue name is what shows, because that is where the macros come from.
    expect(find.text(chicken.n), findsOneWidget);
    expect(find.text(rice.n), findsOneWidget);

    // The whole design in one assertion: a draft on screen, and a log still untouched.
    expect(container.read(appStateProvider).meals, isEmpty);
    container.dispose();
  });

  testWidgets('confirming logs the reviewed macros, computed from the catalogue', (tester) async {
    final container = await pump(
      tester,
      result: AiDraft(answer([
        {'fid': chicken.id, 'name': 'Chicken', 'grams': 200},
      ])),
    );

    await shoot(tester);
    await press(tester, find.text('Log this meal'));

    final meals = container.read(appStateProvider).meals;
    expect(meals, hasLength(1));
    final item = meals.single.items.single;
    expect(item.fid, chicken.id);
    // Not whatever the model said — what the food record says, scaled by the portion.
    expect(item.kcal, chicken.kcal * 2);
    expect(item.p, chicken.p * 2);
    container.dispose();
  });

  testWidgets('editing the grams moves what gets logged', (tester) async {
    final container = await pump(
      tester,
      result: AiDraft(answer([
        {'fid': chicken.id, 'name': 'Chicken', 'grams': 200},
      ])),
    );

    await shoot(tester);
    await tester.enterText(find.byType(NumberBox).first, '100');
    await tester.pumpAndSettle();
    await press(tester, find.text('Log this meal'));

    final item = container.read(appStateProvider).meals.single.items.single;
    expect(item.g, 100);
    expect(item.kcal, chicken.kcal);
    container.dispose();
  });

  testWidgets('confirming merges into a meal that is already in that slot', (tester) async {
    // The test that catches someone reaching for st.meals.add instead of addMealItem: toast and a
    // photographed plate in the same slot are one meal, not two.
    //
    // Driven through the generic row, which logs against the unassigned slot, so the existing meal
    // is seeded the same way. That exercises exactly the same merge in addMealItem as a slot card
    // would, without depending on where a small icon lands in an 800x600 viewport.
    final initial = onState();
    initial.meals.add(Meal(
      id: 'ml_existing',
      d: today,
      items: [MealItem(n: 'Toast', g: 40, kcal: 100, p: 3, c: 20, f: 1)],
    ));

    final container = await pump(
      tester,
      initial: initial,
      result: AiDraft(answer([
        {'fid': chicken.id, 'name': 'Chicken', 'grams': 100},
      ])),
    );

    await shoot(tester);
    await press(tester, find.text('Log this meal'));

    final meals = container.read(appStateProvider).meals;
    expect(meals, hasLength(1), reason: 'a second meal in the same slot means slot merging broke');
    expect(meals.single.items, hasLength(2));
    expect(meals.single.id, 'ml_existing', reason: 'it joined the existing meal, not replaced it');
    container.dispose();
  });

  testWidgets('a failure offers a real way to log it by hand', (tester) async {
    final container = await pump(
      tester,
      result: const AiFailure(AiFailureKind.offline),
    );

    await shoot(tester);

    expect(find.text('That did not work'), findsOneWidget);
    expect(find.textContaining('No connection'), findsOneWidget);

    // Not a dead end: the food still got eaten and the day still has to add up.
    await press(tester, find.text('Log it by hand'));
    expect(find.text('Add food'), findsOneWidget);
    expect(container.read(appStateProvider).meals, isEmpty);
    container.dispose();
  });

  testWidgets('a refused key says so rather than blaming the photo', (tester) async {
    final container = await pump(tester, result: const AiFailure(AiFailureKind.badKey));
    await shoot(tester);
    expect(find.textContaining('refused'), findsOneWidget);
    container.dispose();
  });

  testWidgets('a photo of something that is not food says exactly that', (tester) async {
    final container = await pump(
      tester,
      result: AiDraft(jsonDecode(jsonEncode({
        'confidence': 'low',
        'notFood': true,
        'items': <Object>[],
      }))),
    );

    await shoot(tester);
    expect(find.text('That does not look like a meal.'), findsOneWidget);
    expect(container.read(appStateProvider).meals, isEmpty);
    container.dispose();
  });

  testWidgets('cancelling the picker leaves the sheet where it was', (tester) async {
    final container = await pump(
      tester,
      cancelPicker: true,
      result: AiDraft(answer([])),
    );

    await press(tester, find.text('Log from a photo').last);
    await press(tester, find.text('Take a photo'));

    // Backing out of the camera is not a failure and must not be reported as one.
    expect(find.text('That did not work'), findsNothing);
    expect(find.text('Take a photo'), findsOneWidget);
    container.dispose();
  });

  testWidgets('an item can be removed before logging', (tester) async {
    final container = await pump(
      tester,
      result: AiDraft(answer([
        {'fid': chicken.id, 'name': 'Chicken', 'grams': 200},
        {'fid': rice.id, 'name': 'Rice', 'grams': 180},
      ])),
    );

    await shoot(tester);
    expect(find.text(rice.n), findsOneWidget);

    // The app draws its own icons from path strings, so there is no Material Icons data to match
    // on. Scoped to the rice row rather than counted across the tree: the sheet sits on top of a
    // screen that has dismiss glyphs of its own, and "the last xmark" is not reliably this one.
    final riceRow = find
        .ancestor(of: find.text(rice.n), matching: find.byType(Row))
        .first;
    await press(
      tester,
      find.descendant(
        of: riceRow,
        matching: find.byWidgetPredicate((w) => w is AppIcon && w.name == 'xmark'),
      ),
    );

    expect(find.text(rice.n), findsNothing);
    expect(find.text(chicken.n), findsOneWidget);

    await press(tester, find.text('Log this meal'));
    expect(container.read(appStateProvider).meals.single.items, hasLength(1));
    container.dispose();
  });

  // ---------- keeping the photograph ----------

  testWidgets('confirming stores the photo and hangs it on the meal', (tester) async {
    final container = await pump(
      tester,
      result: AiDraft(answer([
        {'fid': chicken.id, 'name': 'Chicken', 'grams': 200},
      ])),
    );

    await shoot(tester);
    // Still nothing on disk: the file is written at Confirm, with everything else.
    expect(photos.files, isEmpty);

    await press(tester, find.text('Log this meal'));

    final meal = container.read(appStateProvider).meals.single;
    expect(meal.photo, isNotNull);
    // A name, never a path — an app documents path is re-created on every iOS reinstall.
    expect(isMealPhotoName(meal.photo!), isTrue);
    expect(photos.files[meal.photo], jpeg, reason: 'the reference has to resolve to the bytes');
    container.dispose();
  });

  testWidgets('with keeping switched off, the meal is logged and nothing is stored',
      (tester) async {
    final initial = onState();
    initial.ai.feature(aiMealPhoto).keepPhotos = false;

    final container = await pump(
      tester,
      initial: initial,
      result: AiDraft(answer([
        {'fid': chicken.id, 'name': 'Chicken', 'grams': 200},
      ])),
    );

    await shoot(tester);
    await press(tester, find.text('Log this meal'));

    // The setting is about the picture, never about the log.
    expect(container.read(appStateProvider).meals.single.items, hasLength(1));
    expect(photos.files, isEmpty);
    expect(container.read(appStateProvider).meals.single.photo, isNull);
    container.dispose();
  });

  testWidgets('a store that cannot write still logs the meal', (tester) async {
    // A full disk, or a documents directory that will not open. The photograph is decoration on a
    // record that is already complete, and losing it must not cost the user their breakfast.
    final container = await pump(
      tester,
      result: AiDraft(answer([
        {'fid': chicken.id, 'name': 'Chicken', 'grams': 200},
      ])),
    );
    photos.refuseWrites = true;

    await shoot(tester);
    await press(tester, find.text('Log this meal'));

    final meal = container.read(appStateProvider).meals.single;
    expect(meal.items, hasLength(1));
    expect(meal.photo, isNull, reason: 'a name pointing at a file that was never written');
    container.dispose();
  });

  testWidgets('photographing the same slot again replaces the picture', (tester) async {
    final container = await pump(
      tester,
      result: AiDraft(answer([
        {'fid': chicken.id, 'name': 'Chicken', 'grams': 200},
      ])),
    );

    await shoot(tester);
    await press(tester, find.text('Log this meal'));
    final first = container.read(appStateProvider).meals.single.photo;

    await shoot(tester);
    await press(tester, find.text('Log this meal'));
    final second = container.read(appStateProvider).meals.single.photo;

    expect(second, isNot(first),
        reason: 'the plate the user was looking at while confirming is the one to show');
    // ...and the one it replaced is deleted now, not left for the next boot sweep to find.
    expect(photos.files.keys, [second]);
    container.dispose();
  });

  testWidgets('a photographed meal shows its picture on the day', (tester) async {
    final container = await pump(
      tester,
      result: AiDraft(answer([
        {'fid': chicken.id, 'name': 'Chicken', 'grams': 200},
      ])),
    );

    memoryImages() => find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage,
        skipOffstage: false);
    expect(memoryImages(), findsNothing);

    await shoot(tester);
    await press(tester, find.text('Log this meal'));
    await tester.pumpAndSettle();

    expect(memoryImages(), findsWidgets);
    container.dispose();
  });

  testWidgets('a meal whose file has gone renders as an ordinary meal', (tester) async {
    // What every restored backup looks like: the name comes across in the JSON and the bytes do
    // not. A missing photo is the normal case, not an error state, so nothing may be left behind
    // on the card — no placeholder, no gap.
    final initial = onState();
    initial.meals.add(Meal(
      id: 'ml_restored',
      d: today,
      photo: 'mpfromanotherphone.jpg',
      items: [MealItem(n: 'Toast', g: 40, kcal: 100, p: 3, c: 20, f: 1)],
    ));

    final container = await pump(tester, initial: initial, result: AiDraft(answer([])));
    await tester.pumpAndSettle();

    expect(find.textContaining('Toast', skipOffstage: false), findsWidgets);
    expect(
        find.byWidgetPredicate((w) => w is Image && w.image is MemoryImage, skipOffstage: false),
        findsNothing);
    container.dispose();
  });
}

/// Returns canned raw JSON, so the real sanitizer runs in every test above.
class _FakeVision implements AiProvider {
  const _FakeVision(this.result);

  final AiResult result;

  @override
  bool get isAvailable => true;

  @override
  String get label => 'Claude Opus 5';

  @override
  Future<AiResult> run(AiRequest request) async => result;
}
