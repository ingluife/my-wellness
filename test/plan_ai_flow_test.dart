import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_open_gym/data/ai/ai_key_store.dart';
import 'package:my_open_gym/data/models/app_state.dart';
import 'package:my_open_gym/domain/ai/ai_provider.dart';
import 'package:my_open_gym/domain/exercises.dart';
import 'package:my_open_gym/domain/i18n.dart';
import 'package:my_open_gym/state/ai_provider.dart';
import 'package:my_open_gym/state/app_state_provider.dart';
import 'package:my_open_gym/ui/app.dart';
import 'package:my_open_gym/ui/sheets/sheet_service.dart';
import 'package:my_open_gym/ui/widgets/controls/app_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';

/// The drafting flow, end to end, with a canned answer instead of a provider.
///
/// The claim under test throughout: **nothing reaches the state before Save.** A draft is a
/// proposal, and a proposal that had already rewritten the plan would not be one.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
    await Exercises.instance.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Real dataset ids so the sanitiser's lookup is the real one.
  const bench = '0025';
  const squat = '0043';
  const row = '0027';

  Map<String, Object?> answer({Map<String, Object?>? week}) => {
        'routines': [
          {
            'name': 'Push',
            'emoji': 'barbell',
            'exercises': [
              {'id': bench, 'sets': 4, 'reps': 8},
            ],
          },
          {
            'name': 'Legs',
            'emoji': 'legs',
            'exercises': [
              {'id': squat, 'sets': 4, 'reps': 8},
              {'id': row, 'sets': 3, 'reps': 10},
            ],
          },
        ],
        'week': ?week,
        'rationale': 'Two sessions covering the whole body.',
      };

  /// A profile with the feature switched on and a key present, so the gate opens.
  AppState enabled() {
    final s = AppState.defaults();
    s.ai.feature(aiWorkoutPlan)
      ..on = true
      ..provider = 'anthropic';
    return s;
  }

  Future<ProviderContainer> pump(WidgetTester tester, AiResult result,
      {AppState? initial}) async {
    final container = ProviderContainer(overrides: [
      aiKeyStoreProvider.overrideWithValue(MemoryAiKeyStore(const {'anthropic': 'k'})),
      aiWorkoutPlanProvider.overrideWithValue(_CannedAi(result)),
    ]);
    container.read(appStateProvider.notifier).replaceState(initial ?? enabled());
    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyOpenGymApp()));
    await tester.pumpAndSettle();
    appNavigatorKey.currentContext!.go('/plan');
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> tap(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  /// Open the sheet and drive it as far as the review step.
  ///
  /// Finds by `t(...)` rather than by the English literal so the same helper works in the
  /// phone-width test below, which runs the whole flow in German.
  Future<void> draft(WidgetTester tester) async {
    await tap(tester, find.text(t('Draft a routine with AI')));
    await tap(tester, find.widgetWithText(AppButton, t('Draft it')));
  }

  testWidgets('the entry point is absent until the feature is set up', (tester) async {
    // Deliberately no aiWorkoutPlanProvider override: the real gate is the thing under test, and
    // a canned provider reports itself available and would sail straight past it.
    final container = ProviderContainer();
    container.read(appStateProvider.notifier).replaceState(AppState.defaults());
    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyOpenGymApp()));
    await tester.pumpAndSettle();
    appNavigatorKey.currentContext!.go('/plan');
    await tester.pumpAndSettle();

    // Not a dead button: the row is there, but it says what it is and leads to setup.
    expect(find.text('Draft a routine with AI'), findsNothing);
    expect(find.text('Set up AI routines'), findsOneWidget);

    await tap(tester, find.text('Set up AI routines'));
    expect(GoRouter.of(appNavigatorKey.currentContext!).state.uri.path, '/settings/ai');
    container.dispose();
  });

  testWidgets('a draft is shown but nothing is saved yet', (tester) async {
    final container = await pump(tester, AiDraft(answer()));
    await draft(tester);

    // The draft is on screen...
    expect(find.text('Push'), findsWidgets);
    expect(find.text('Legs'), findsWidgets);
    expect(find.textContaining('Two sessions'), findsOneWidget);

    // ...and the plan is untouched.
    expect(container.read(appStateProvider).routines, isEmpty);
    expect(container.read(appStateProvider).week.values.where((v) => v.isNotEmpty), isEmpty);
    container.dispose();
  });

  testWidgets('leaving the review writes nothing', (tester) async {
    final container = await pump(tester, AiDraft(answer()));
    await draft(tester);
    await tap(tester, find.widgetWithText(AppButton, 'Start over'));

    expect(container.read(appStateProvider).routines, isEmpty);
    container.dispose();
  });

  testWidgets('Save writes the routines, and the week they were scheduled for', (tester) async {
    final container = await pump(tester, AiDraft(answer(week: {'1': 0, '4': 1})));
    await draft(tester);
    await tap(tester, find.widgetWithText(AppButton, 'Save plan'));

    final s = container.read(appStateProvider);
    expect(s.routines.map((r) => r.name), ['Push', 'Legs']);
    expect(s.routines.first.ex.single.id, bench);
    expect(s.routines.last.ex.map((e) => e.id), [squat, row]);

    // The week points at the routines that were actually created, by their minted ids.
    expect(s.week['1'], s.routines.first.id);
    expect(s.week['4'], s.routines.last.id);
    container.dispose();
  });

  testWidgets('saving appends rather than replacing what is already there', (tester) async {
    // The same choice loadStarterPlan makes: nobody asked for their existing routines to go.
    final initial = enabled()..routines.add(Routine(id: 'mine', name: 'My own'));
    final container = await pump(tester, AiDraft(answer()), initial: initial);
    await draft(tester);
    await tap(tester, find.widgetWithText(AppButton, 'Save plan'));

    final s = container.read(appStateProvider);
    expect(s.routines.map((r) => r.name), ['My own', 'Push', 'Legs']);
    container.dispose();
  });

  testWidgets('a saved exercise carries a config the rest of the app understands',
      (tester) async {
    final container = await pump(tester, AiDraft(answer()));
    await draft(tester);
    await tap(tester, find.widgetWithText(AppButton, 'Save plan'));

    final cfg = container.read(appStateProvider).routines.first.ex.single;
    expect(cfg.id, bench);
    expect(cfg.sets, 4);
    expect(cfg.reps, 8);
    // defaultConfig filled the rest in, which is what makes a drafted exercise behave like a
    // hand-added one in the workout screen and under progression.
    expect(cfg.weight, isNotNull);
    container.dispose();
  });

  // One test per kind rather than a loop inside one: the sheet is a route on the global
  // navigator, so a second iteration would open its sheet on top of the first one's.
  for (final kind in AiFailureKind.values) {
    if (kind == AiFailureKind.cancelled) continue;
    testWidgets('$kind says something, and saves nothing', (tester) async {
      final container = await pump(tester, AiFailure(kind));
      await draft(tester);

      expect(find.text('That did not work'), findsOneWidget);
      expect(find.widgetWithText(AppButton, 'Try again'), findsOneWidget);
      // Whatever went wrong, the plan is where it was.
      expect(container.read(appStateProvider).routines, isEmpty);
      container.dispose();
    });
  }

  testWidgets('the review fits a phone, in a language that runs long', (tester) async {
    // German is the stress case for this sheet: 'Trainingspläne', 'Von vorn beginnen' and a
    // three-line privacy sentence all have to fit in the same box English needs one line for.
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // runAsync, not a bare await: setLang reads the pack out of the asset bundle, which is real
    // I/O, and real I/O inside testWidgets' fake-async zone never completes. This deadlocks
    // rather than failing, which is a memorable half hour if you meet it without the comment.
    await tester.runAsync(() => I18n.instance.setLang('de'));
    addTearDown(() => I18n.instance.setLang('en'));

    final container = await pump(tester, AiDraft(answer(week: {'1': 0, '4': 1})),
        initial: enabled()..lang = 'de');
    await draft(tester);

    // testWidgets fails on an unexpected exception by itself, and an overflow is one — this is
    // here to say that is the point of the test rather than a side effect of it.
    expect(tester.takeException(), isNull);
    expect(find.text('Push'), findsWidgets);
    container.dispose();
  });

  testWidgets('an answer with nothing usable in it is its own message', (tester) async {
    // Distinguishable from a provider failure: the request worked, the content did not survive.
    final container = await pump(tester, AiDraft(const {
      'routines': [
        {
          'name': 'Ghost',
          'exercises': [
            {'id': 'invented', 'sets': 3, 'reps': 10}
          ],
        }
      ],
    }));
    await draft(tester);

    expect(find.text('Nothing usable came back'), findsOneWidget);
    expect(container.read(appStateProvider).routines, isEmpty);
    container.dispose();
  });
}

/// An [AiProvider] that answers instantly with whatever it was built with.
class _CannedAi implements AiProvider {
  const _CannedAi(this.result);

  final AiResult result;

  @override
  bool get isAvailable => true;

  @override
  String get label => 'Test Model';

  @override
  Future<AiResult> run(AiRequest request) async => result;
}
