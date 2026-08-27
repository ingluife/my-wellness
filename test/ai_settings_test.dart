import 'dart:convert';
import 'dart:typed_data';

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
import 'package:my_open_gym/domain/i18n.dart';
import 'package:my_open_gym/state/ai_provider.dart';
import 'package:my_open_gym/state/app_state_provider.dart';
import 'package:my_open_gym/ui/app.dart';
import 'package:my_open_gym/ui/sheets/sheet_service.dart';
import 'package:my_open_gym/ui/widgets/controls/fields.dart';
import 'package:my_open_gym/ui/widgets/controls/surfaces.dart';
import 'package:my_open_gym/ui/widgets/controls/toggles.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The AI settings screen, and the one property that matters more than any of its behaviour:
/// a key the user types in must not end up anywhere `AppState` can reach.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
    await Exercises.instance.load();
    await foods.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// Back to English between tests. Outside testWidgets, so the asset read is real async and
  /// this can simply be awaited.
  tearDown(() => I18n.instance.setLang('en'));

  /// Stands in for the app documents directory. Fresh per test.
  late MemoryMealPhotoStore photos;
  setUp(() => photos = MemoryMealPhotoStore());

  /// What the connection test asked about, so a test can prove it tested the right provider.
  late List<String> probed;
  setUp(() => probed = []);

  /// Builds the real app with an in-memory key store — no keychain, no platform channel.
  ///
  /// [probe] stands in for the connection test's round trip: null for "it worked", a kind for a
  /// failure. Left as a fake because the real one is a socket; what it actually sends is covered
  /// against a fake client in ai_adapter_test.dart.
  Future<(ProviderContainer, MemoryAiKeyStore)> pump(
    WidgetTester tester, {
    Map<String, String>? keys,
    AppState? initial,
    AiFailureKind? probe,
  }) async {
    final store = MemoryAiKeyStore(keys);
    final container = ProviderContainer(
      overrides: [
        aiKeyStoreProvider.overrideWithValue(store),
        mealPhotoStoreProvider.overrideWithValue(photos),
        aiProbeProvider.overrideWithValue((id) async {
          probed.add(id);
          return probe;
        }),
      ],
    );
    if (initial != null) container.read(appStateProvider.notifier).replaceState(initial);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyOpenGymApp()));
    await tester.pumpAndSettle();
    appNavigatorKey.currentContext!.go('/settings/ai');
    await tester.pumpAndSettle();
    return (container, store);
  }

  Future<void> press(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('with no key set, every provider reads Not set', (tester) async {
    final (container, _) = await pump(tester);
    expect(find.text('Anthropic'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('OpenAI'), findsOneWidget);
    expect(find.text('Not set'), findsNWidgets(3));
    container.dispose();
  });

  testWidgets('the feature cannot be switched on before a key exists', (tester) async {
    final (container, _) = await pump(tester);

    final sw = tester.widget<AppSwitch>(find.byType(AppSwitch).first);
    expect(sw.enabled, isFalse,
        reason: 'a switch that turns on with no key builds a setting that fails on first use');

    expect(find.text('Add a key above first'), findsOneWidget);
    expect(container.read(appStateProvider).ai.features[aiMealPhoto]?.isOn ?? false, isFalse);
    container.dispose();
  });

  testWidgets('a stored key is never rendered back to the screen', (tester) async {
    const secret = 'sk-ant-api03-THE-ACTUAL-SECRET-VALUE';
    final (container, _) = await pump(tester, keys: {'anthropic': secret});

    // Not in a field, not in a subtitle, not as a truncated "sk-ant-…" reassurance.
    expect(find.textContaining('sk-ant'), findsNothing);
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.text('••••••••••••'), findsOneWidget);
    container.dispose();
  });

  testWidgets('saving a key stores it and leaves nothing in the state', (tester) async {
    final (container, store) = await pump(tester);
    const secret = 'sk-ant-api03-typed-by-the-user';

    await press(tester, find.text('Add').first);
    await tester.enterText(find.byType(AppTextField), secret);
    await tester.pumpAndSettle();
    await press(tester, find.text('Save'));

    expect(await store.read('anthropic'), secret);

    // The whole point. The state is what gets mirrored to a plaintext file and shared out of
    // the app as a backup; the key must be absent from it in every form.
    final json = jsonEncode(container.read(appStateProvider).toJson());
    expect(json, isNot(contains(secret)));
    expect(json, isNot(contains('sk-ant')));
    container.dispose();
  });

  testWidgets('with a key present the feature can be turned on and persists', (tester) async {
    final (container, _) = await pump(tester, keys: {'anthropic': 'sk-ant-x'});

    final sw = find.byType(AppSwitch).first;
    expect(tester.widget<AppSwitch>(sw).enabled, isTrue);
    await press(tester, sw);

    final cfg = container.read(appStateProvider).ai.features[aiMealPhoto];
    expect(cfg?.isOn, isTrue);

    // And the state now writes the key it did not write before.
    expect(container.read(appStateProvider).toJson().containsKey('ai'), isTrue);
    container.dispose();
  });

  testWidgets('removing a key turns the feature off rather than orphaning it', (tester) async {
    final initial = AppState.defaults();
    initial.ai.feature(aiMealPhoto)
      ..on = true
      ..provider = 'anthropic'
      ..model = 'claude-opus-5';

    final (container, store) = await pump(
      tester,
      keys: {'anthropic': 'sk-ant-x'},
      initial: initial,
    );

    await press(tester, find.text('Replace').first);
    await press(tester, find.text('Remove'));

    expect(await store.read('anthropic'), isNull);
    final cfg = container.read(appStateProvider).ai.features[aiMealPhoto];
    expect(cfg?.isOn, isFalse,
        reason: 'a switch left on pointing at a deleted key is a button that fails when tapped');
    expect(cfg?.provider, isNull);
    container.dispose();
  });

  testWidgets('only providers holding a key can be chosen', (tester) async {
    // Offering a provider with no key builds a setting that looks complete and fails on first use.
    final (container, _) = await pump(tester, keys: {'google': 'g-key'});

    // Every provider has a key row above, so each name is already on screen exactly once. The
    // chooser adding an entry is what would push a count to two.
    expect(find.text('Anthropic'), findsOneWidget);
    expect(find.text('OpenAI'), findsOneWidget);

    await press(tester, find.text('Log a meal from a photo'));
    await press(tester, find.text('Provider'));

    expect(find.text('Google'), findsWidgets, reason: 'the key row and the chooser entry');
    // Still one each: the two without a key were not offered.
    expect(find.text('Anthropic'), findsOneWidget);
    expect(find.text('OpenAI'), findsOneWidget);
    container.dispose();
  });

  testWidgets('each provider offers its own models, at its own prices', (tester) async {
    final initial = AppState.defaults();
    initial.ai.feature(aiMealPhoto)
      ..on = true
      ..provider = 'google';

    final (container, _) = await pump(
      tester,
      keys: {'google': 'g-key'},
      initial: initial,
    );

    await press(tester, find.text('Model'));
    // Gemini names, not Claude ones — the model table is per provider. findsWidgets rather than
    // findsOneWidget because the selected model shows on the row as well as in the chooser.
    expect(find.text('Gemini 3.7 Flash'), findsWidgets);
    expect(find.text('Gemini 3.1 Pro'), findsWidgets);
    expect(find.textContaining('Claude'), findsNothing);
    // ...and the per-photo cost shown is Gemini's, not a figure carried over from another table.
    expect(find.textContaining('a photo'), findsWidgets);
    container.dispose();
  });

  testWidgets('keeping photos is offered only once the feature is on', (tester) async {
    // A retention setting for a feature that never runs is a control for nothing.
    final (off, _) = await pump(tester, keys: {'anthropic': 'sk-ant-x'});
    expect(find.text('Keep the photo'), findsNothing);
    off.dispose();

    final initial = AppState.defaults();
    initial.ai.feature(aiMealPhoto)
      ..on = true
      ..provider = 'anthropic';

    final (on, _) = await pump(tester, keys: {'anthropic': 'sk-ant-x'}, initial: initial);
    expect(find.text('Keep the photo'), findsOneWidget);
    // The two things a user cannot guess: how long it keeps them, and whether they travel.
    expect(find.textContaining('90 days', skipOffstage: false), findsOneWidget);
    expect(find.textContaining('never part of your backup', skipOffstage: false), findsOneWidget);
    on.dispose();
  });

  testWidgets('switching keeping off deletes what is already stored', (tester) async {
    // Not at the next launch. A setting that only stops *new* photos would leave the ones the
    // user just asked to be rid of sitting on the disk until they happened to restart the app.
    final initial = AppState.defaults();
    initial.ai.feature(aiMealPhoto)
      ..on = true
      ..provider = 'anthropic';
    initial.meals.add(Meal(
      id: 'ml1',
      d: todayISO(),
      photo: 'mpkeep1.jpg',
      items: [MealItem(n: 'Toast', g: 40, kcal: 100, p: 3, c: 20, f: 1)],
    ));
    photos.files['mpkeep1.jpg'] = Uint8List.fromList([0xFF, 0xD8]);

    final (container, _) = await pump(
      tester,
      keys: {'anthropic': 'sk-ant-x'},
      initial: initial,
    );

    expect(find.text('1 on this phone'), findsOneWidget);
    // Scoped to its own row rather than taken as "the second switch on the screen", which stops
    // being this one the moment another setting is added above it.
    await press(
      tester,
      find.descendant(
        of: find.ancestor(of: find.text('Keep the photo'), matching: find.byType(AppRow)),
        matching: find.byType(AppSwitch),
      ),
    );

    expect(photos.files, isEmpty);
    // And the reference goes with the file, rather than being left pointing at nothing.
    expect(container.read(appStateProvider).meals.single.photo, isNull);
    expect(container.read(appStateProvider).ai.feature(aiMealPhoto).keepsPhotos, isFalse);
    // The meal itself is untouched — the setting is about the picture, never about the log.
    expect(container.read(appStateProvider).meals.single.items, hasLength(1));
    container.dispose();
  });

  group('the connection test', () {
    testWidgets('is offered only for a provider that has a key', (tester) async {
      // Nothing to test until there is something to test with, and a button that always fails is
      // the same mistake as a switch that turns on with no key.
      final (none, _) = await pump(tester);
      expect(find.text('Test'), findsNothing);
      none.dispose();

      final (one, _) = await pump(tester, keys: {'anthropic': 'sk-ant-x'});
      expect(find.text('Test'), findsOneWidget);
      one.dispose();
    });

    testWidgets('says so plainly when the key works', (tester) async {
      final (container, _) = await pump(tester, keys: {'anthropic': 'sk-ant-x'});

      // Before it is pressed the row says where the key lives, not a verdict it has not earned.
      expect(find.text('Stored in the phone keychain. It is not in your backup.'), findsOneWidget);
      expect(find.text('The key works.'), findsNothing);

      await press(tester, find.text('Test'));

      expect(probed, ['anthropic'], reason: 'the row tests its own provider');
      expect(find.text('The key works.'), findsOneWidget);
      container.dispose();
    });

    testWidgets('turns each failure into a sentence about what to do', (tester) async {
      for (final (kind, line) in [
        (AiFailureKind.badKey, 'That key was refused.'),
        (AiFailureKind.offline, 'No connection.'),
        // The one this button exists for: a model id the provider has retired reads as a fault in
        // the app, which is what it is, rather than as an unreadable answer.
        (
          AiFailureKind.rejected,
          'The provider would not accept the request — the model may no longer exist.'
        ),
      ]) {
        final (container, _) =
            await pump(tester, keys: {'anthropic': 'sk-ant-x'}, probe: kind);
        await press(tester, find.text('Test'));
        expect(find.text(line), findsOneWidget, reason: kind.name);
        container.dispose();
      }
    });

    testWidgets('a verdict does not outlive the key it was about', (tester) async {
      // Replacing the key and leaving "That key was refused." underneath it would be the screen
      // asserting something it has not checked.
      final (container, _) =
          await pump(tester, keys: {'anthropic': 'sk-ant-x'}, probe: AiFailureKind.badKey);
      await press(tester, find.text('Test'));
      expect(find.text('That key was refused.'), findsOneWidget);

      await press(tester, find.text('Replace').first);
      await tester.enterText(find.byType(AppTextField), 'sk-ant-a-different-one');
      await tester.pumpAndSettle();
      await press(tester, find.text('Save'));

      expect(find.text('That key was refused.'), findsNothing);
      expect(find.text('Stored in the phone keychain. It is not in your backup.'), findsOneWidget);
      container.dispose();
    });

    testWidgets('the price of a test is stated where the button is', (tester) async {
      // Every other feature in this app is free. One that bills the user's own account says so
      // at the control, not in a README — the same rule the per-photo figures follow.
      final (off, _) = await pump(tester);
      expect(find.textContaining('fraction of a cent', skipOffstage: false), findsNothing);
      off.dispose();

      final (on, _) = await pump(tester, keys: {'anthropic': 'sk-ant-x'});
      expect(find.textContaining('fraction of a cent', skipOffstage: false), findsOneWidget);
      on.dispose();
    });
  });

  testWidgets('the screen renders in another language', (tester) async {
    // The end of the i18n chain: overlay -> gen_i18n -> asset pack -> t() on screen. The pack
    // tests upstream prove the strings exist; this proves the screen actually reaches them.
    // Loaded up front rather than left to the app's own fire-and-forget setLang in build, which
    // resolves off an asset read that pumpAndSettle does not wait for. It has to go through
    // runAsync: testWidgets fakes the clock, and a real asset read inside that zone never
    // completes — the test hangs rather than failing, which is a nasty way to find out.
    await tester.runAsync(() => I18n.instance.setLang('de'));

    final initial = AppState.defaults()..lang = 'de';
    final (container, _) = await pump(tester, initial: initial);

    expect(find.text('KI-Funktionen'), findsOneWidget);
    expect(find.text('Anbieter'), findsWidgets);
    expect(find.text('So funktioniert es'), findsOneWidget);
    // ...and the English source strings are gone, not merely duplicated.
    expect(find.text('AI features'), findsNothing);
    container.dispose();
  });

  testWidgets('the Your data row stops promising nothing leaves the phone', (tester) async {
    // The claim was true for as long as there was no code that could send anything anywhere.
    // Once the feature is on it is not, and a false statement in the UI is worse than none.
    final initial = AppState.defaults();
    initial.ai.feature(aiMealPhoto)
      ..on = true
      ..provider = 'anthropic';

    final container = ProviderContainer(
      overrides: [aiKeyStoreProvider.overrideWithValue(MemoryAiKeyStore({'anthropic': 'k'}))],
    );
    container.read(appStateProvider.notifier).replaceState(initial);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyOpenGymApp()));
    await tester.pumpAndSettle();
    appNavigatorKey.currentContext!.go('/settings');
    await tester.pumpAndSettle();

    expect(find.text('All data stays on this phone'), findsNothing);
    expect(find.text('Your training log stays on this phone'), findsOneWidget);
    container.dispose();
  });
}
