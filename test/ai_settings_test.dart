import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_wellness/data/ai/ai_key_store.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/data/repositories/meal_photo_store.dart';
import 'package:my_wellness/domain/ai/ai_provider.dart';
import 'package:my_wellness/domain/exercises.dart';
import 'package:my_wellness/domain/foods.dart';
import 'package:my_wellness/domain/format.dart';
import 'package:my_wellness/domain/i18n.dart';
import 'package:my_wellness/state/ai_provider.dart';
import 'package:my_wellness/state/app_state_provider.dart';
import 'package:my_wellness/ui/app.dart';
import 'package:my_wellness/ui/sheets/sheet_service.dart';
import 'package:my_wellness/ui/widgets/controls/fields.dart';
import 'package:my_wellness/ui/widgets/controls/surfaces.dart';
import 'package:my_wellness/ui/widgets/controls/toggles.dart';
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

  /// The same, for the typed-but-unsaved path — provider id and the literal string it was asked
  /// to test, so a test can prove Save never ran behind it.
  late List<(String, String)> probedKeys;
  setUp(() => probedKeys = []);

  /// Builds the real app with an in-memory key store — no keychain, no platform channel.
  ///
  /// [probe] stands in for the connection test's round trip: null for "it worked", a kind for a
  /// failure. Left as a fake because the real one is a socket; what it actually sends is covered
  /// against a fake client in ai_adapter_test.dart. [probeKey] is the same for the unsaved-key
  /// path.
  Future<(ProviderContainer, MemoryAiKeyStore)> pump(
    WidgetTester tester, {
    Map<String, String>? keys,
    AppState? initial,
    AiFailureKind? probe,
    AiFailureKind? probeKey,
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
        aiProbeKeyProvider.overrideWithValue((id, key) async {
          probedKeys.add((id, key));
          return probeKey;
        }),
      ],
    );
    if (initial != null) container.read(appStateProvider.notifier).replaceState(initial);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyWellnessApp()));
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

    // Every feature, not just the first: each one is its own switch and its own way to build a
    // setting that looks complete and fails on first use.
    for (final sw in tester.widgetList<AppSwitch>(find.byType(AppSwitch))) {
      expect(sw.enabled, isFalse,
          reason: 'a switch that turns on with no key builds a setting that fails on first use');
    }
    expect(find.text('Add a key above first'), findsNWidgets(aiFeatures.length));
    for (final f in aiFeatures) {
      expect(container.read(appStateProvider).ai.features[f]?.isOn ?? false, isFalse, reason: f);
    }
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
    // The bug this guards: the Provider row displays the one usable provider as already chosen
    // (see its own "value: chosen ?? usable.first" comment) whether or not anything was ever
    // written to state. With only one provider there is nothing left to pick, so turning the
    // switch on has to be the moment that choice becomes real — otherwise the switch reads as on
    // while `aiMealPhotoProvider` still sees no provider and stays disabled forever.
    expect(cfg?.provider, 'anthropic');

    // And the state now writes the key it did not write before.
    expect(container.read(appStateProvider).toJson().containsKey('ai'), isTrue);
    container.dispose();
  });

  testWidgets('adding the first key defaults the provider, not only the switch',
      (tester) async {
    // The other half of the same bug, reached the other way round: a key can be added before the
    // switch is ever touched, and the same silent gap would leave the feature stuck off even once
    // the switch is turned on afterwards through a fresh rebuild that never re-runs this logic.
    final (container, _) = await pump(tester);

    await press(tester, find.text('Add').first);
    await tester.enterText(find.byType(AppTextField), 'sk-ant-x');
    await tester.pumpAndSettle();
    await press(tester, find.text('Save'));

    final cfg = container.read(appStateProvider).ai.features[aiMealPhoto];
    expect(cfg?.provider, 'anthropic');
    // Saving a key is not the same as turning the feature on — that is still a separate, explicit
    // step.
    expect(cfg?.isOn ?? false, isFalse);
    container.dispose();
  });

  testWidgets('a second key does not steal the provider the first one set', (tester) async {
    // Auto-selecting is only for "nothing chosen yet". A user who already has a real choice on
    // record — made either explicitly or by the same default — must not have it silently swapped
    // out from under them by adding a second provider's key.
    final initial = AppState.defaults();
    initial.ai.feature(aiMealPhoto).provider = 'anthropic';
    final (container, _) =
        await pump(tester, keys: {'anthropic': 'sk-ant-x'}, initial: initial);

    await press(tester, find.text('Add').first);
    await tester.enterText(find.byType(AppTextField), 'g-key');
    await tester.pumpAndSettle();
    await press(tester, find.text('Save'));

    expect(container.read(appStateProvider).ai.features[aiMealPhoto]?.provider, 'anthropic');
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
    await press(tester, find.text('Provider').first);

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
    expect(find.text('Gemini 3.6 Flash'), findsWidgets);
    expect(find.textContaining('Claude'), findsNothing);
    // ...and the per-photo cost shown is Gemini's, not a figure carried over from another table.
    expect(find.textContaining('a photo'), findsWidgets);
    container.dispose();
  });

  testWidgets('a model can be set for a provider that is not the active one', (tester) async {
    // The whole point of moving Model onto each provider's own row: it is not gated on that
    // provider currently being the one running the feature. Setting Google's model while
    // Anthropic is active must not require switching to Google first.
    final initial = AppState.defaults();
    initial.ai.feature(aiMealPhoto)
      ..on = true
      ..provider = 'anthropic';

    final (container, _) = await pump(
      tester,
      keys: {'anthropic': 'sk-ant-x', 'google': 'g-key'},
      initial: initial,
    );

    // Google's own Model row, reached without ever touching the Provider selector above. It
    // reads Gemini 3.6 Flash because that is the table's first entry and so its default — see
    // aiModels, where Google deliberately does not lead with Pro.
    await press(tester, find.text('Gemini 3.6 Flash').first);
    await press(tester, find.text('Gemini 3.7 Flash').last);

    final cfg = container.read(appStateProvider).ai.feature(aiMealPhoto);
    expect(cfg.models['google'], 'gemini-3.7-flash');
    // The active provider and its own model are untouched by choosing a model for a different one.
    expect(cfg.provider, 'anthropic');
    container.dispose();
  });

  testWidgets('switching the active provider does not forget a model chosen earlier',
      (tester) async {
    // The bug a single shared field had: picking Flash for Google, moving to Anthropic, then
    // back to Google, used to land back on Google's default (Pro) because switching away cleared
    // it. Each provider now keeps its own choice regardless of which one is active.
    final initial = AppState.defaults();
    initial.ai.feature(aiMealPhoto)
      ..on = true
      ..provider = 'google'
      ..models['google'] = 'gemini-3.7-flash';

    final (container, _) = await pump(
      tester,
      keys: {'anthropic': 'sk-ant-x', 'google': 'g-key'},
      initial: initial,
    );

    await press(tester, find.text('Provider').first);
    await press(tester, find.text('Anthropic').last);
    await press(tester, find.text('Provider').first);
    await press(tester, find.text('Google').last);

    expect(container.read(appStateProvider).ai.feature(aiMealPhoto).models['google'],
        'gemini-3.7-flash');
    container.dispose();
  });

  testWidgets('removing a key drops the model chosen for it', (tester) async {
    // A stale choice sitting under a provider with no key left is not a default worth keeping —
    // the next key typed here should not silently inherit whatever the old one had picked.
    final initial = AppState.defaults();
    initial.ai.feature(aiMealPhoto)
      ..on = true
      ..provider = 'anthropic'
      ..models['anthropic'] = 'claude-haiku-4-5';

    final (container, _) =
        await pump(tester, keys: {'anthropic': 'sk-ant-x'}, initial: initial);

    await press(tester, find.text('Replace').first);
    await press(tester, find.text('Remove'));

    expect(container.read(appStateProvider).ai.feature(aiMealPhoto).models, isEmpty);
    container.dispose();
  });

  group('testing a key before it is saved', () {
    testWidgets('the Test button is offered while typing, before Save', (tester) async {
      final (container, store) = await pump(tester);

      await press(tester, find.text('Add').first);
      await tester.enterText(find.byType(AppTextField), 'sk-ant-not-saved-yet');
      await tester.pumpAndSettle();

      await press(tester, find.text('Test').first);

      expect(probedKeys, [('anthropic', 'sk-ant-not-saved-yet')]);
      // The point of the whole feature: nothing was written to the keychain or to state by
      // testing it, only by Save.
      expect(await store.read('anthropic'), isNull);
      expect(container.read(appStateProvider).ai.features[aiMealPhoto], isNull);
      container.dispose();
    });

    testWidgets('a good result reads the same way it does for a saved key', (tester) async {
      final (container, _) =
          await pump(tester, probeKey: null /* success */);

      await press(tester, find.text('Add').first);
      await tester.enterText(find.byType(AppTextField), 'sk-ant-good');
      await tester.pumpAndSettle();
      await press(tester, find.text('Test').first);

      expect(find.text('The key works.'), findsOneWidget);
      container.dispose();
    });

    testWidgets('an empty field does nothing, the same as Save', (tester) async {
      final (container, _) = await pump(tester);
      await press(tester, find.text('Add').first);
      await press(tester, find.text('Test').first);

      expect(probedKeys, isEmpty);
      container.dispose();
    });

    testWidgets('cancelling out does not leave the verdict behind for the next key',
        (tester) async {
      // A test result is a claim about the string that was typed. Leaving it on screen after
      // Cancel would attach that claim to whatever gets typed next instead.
      final (container, _) = await pump(tester, probeKey: AiFailureKind.badKey);

      await press(tester, find.text('Add').first);
      await tester.enterText(find.byType(AppTextField), 'sk-ant-bad');
      await tester.pumpAndSettle();
      await press(tester, find.text('Test').first);
      expect(find.text('That key was refused.'), findsOneWidget);

      await press(tester, find.text('Cancel'));
      await press(tester, find.text('Add').first);
      expect(find.text('That key was refused.'), findsNothing);
      container.dispose();
    });

    testWidgets('replacing a key can be tested before it overwrites the old one',
        (tester) async {
      final (container, store) = await pump(
        tester,
        keys: {'anthropic': 'sk-ant-original'},
        probeKey: AiFailureKind.badKey,
      );

      await press(tester, find.text('Replace').first);
      await tester.enterText(find.byType(AppTextField), 'sk-ant-typo');
      await tester.pumpAndSettle();
      await press(tester, find.text('Test').first);

      expect(probedKeys, [('anthropic', 'sk-ant-typo')]);
      // The original key survives an unsaved, failed test of its replacement.
      expect(await store.read('anthropic'), 'sk-ant-original');
      container.dispose();
    });
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
        // An empty balance must not borrow the rate-limit sentence. "Try again in a minute" is
        // the one piece of advice that is guaranteed not to work here, and it points the user at
        // a key that is fine.
        (
          AiFailureKind.noCredit,
          'The key works, but the account has no credit. Add billing with the provider.'
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
        UncontrolledProviderScope(container: container, child: const MyWellnessApp()));
    await tester.pumpAndSettle();
    appNavigatorKey.currentContext!.go('/settings');
    await tester.pumpAndSettle();

    expect(find.text('All data stays on this phone'), findsNothing);
    expect(find.text('Your training log stays on this phone'), findsOneWidget);
    container.dispose();
  });
}
