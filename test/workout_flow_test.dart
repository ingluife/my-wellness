import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/exercises.dart';
import 'package:my_wellness/domain/format.dart';
import 'package:my_wellness/state/app_state_provider.dart';
import 'package:my_wellness/ui/app.dart';
import 'package:my_wellness/ui/widgets/controls/toggles.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A session, driven the way it is actually used: start it, log sets, watch the rest timer and
/// the working-weight prompt appear at the right moments, finish it.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
    await Exercises.instance.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A loaded barbell lift and a bodyweight one, out of the real catalogue.
  late String lift, bw;
  setUpAll(() {
    lift = Exercises.instance.db.firstWhere((e) => e.bp != 'cardio' && e.eq == 'barbell').id;
    bw = Exercises.instance.db.firstWhere((e) => e.eq == 'body weight').id;
  });

  Future<ProviderContainer> pump(WidgetTester tester, AppState initial) async {
    final container = ProviderContainer();
    container.read(appStateProvider.notifier).replaceState(initial);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyWellnessApp()));
    // The Start disc pulses forever while a workout runs, so this never settles.
    Future<void> beat([int frames = 8]) async {
      for (var i = 0; i < frames; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    await beat();
    // The app opens on Home; the running session is one tap away on the tab bar.
    // Home's today-row also says Resume; the tab bar's is the smaller, bolder one.
    await tester.tap(find.text('Resume').last);
    await beat();
    return container;
  }

  AppState running({required String exId, int sets = 2, bool bodyweight = false}) {
    final target = ExerciseConfig(
      id: exId,
      sets: sets.toDouble(),
      reps: 8,
      weight: bodyweight ? 0 : 60,
      mode: 'reps',
      bodyweight: bodyweight ? true : null,
    );
    return AppState.defaults()
      ..active = ActiveWorkout(
        id: 'a',
        d: todayISO(),
        start: DateTime.now().millisecondsSinceEpoch,
        name: 'Push Day',
        entries: [
          WorkoutEntry(
            id: exId,
            target: target,
            sets: [
              for (var i = 0; i < sets; i++)
                SetLog(w: bodyweight ? 0 : 60, r: 8, done: false)
            ],
          )
        ],
      );
  }

  testWidgets('the session shows its progress and its set rows', (tester) async {
    final container = await pump(tester, running(exId: lift, sets: 3));
    expect(find.text('Push Day'), findsOneWidget);
    expect(find.text(' · 0/3 sets'), findsOneWidget);
    expect(find.text('Exercise 1 / 1'), findsOneWidget);
    // Weight and reps columns, in the profile's unit.
    expect(find.text('WEIGHT (KG)'), findsOneWidget);
    expect(find.text('REPS'), findsOneWidget);
    expect(find.byType(AppCheck), findsNWidgets(3));
    container.dispose();
  });

  testWidgets('a bodyweight exercise drops the weight column entirely', (tester) async {
    final container = await pump(tester, running(exId: bw, bodyweight: true));
    // One stepper per row, and it counts reps.
    expect(find.text('REPS'), findsOneWidget);
    expect(find.text('WEIGHT (KG)'), findsNothing);
    expect(find.text('ADDED (KG)'), findsNothing);
    container.dispose();
  });

  testWidgets('checking a set starts the rest timer, and the last set does not',
      (tester) async {
    final container = await pump(tester, running(exId: lift, sets: 2));
    final ui = container.read(uiProvider);

    // The set rows sit below the fold on an 800px viewport.
    await tester.ensureVisible(find.byType(AppCheck).first);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byType(AppCheck).first);
    await tester.pump(const Duration(milliseconds: 60));
    expect(container.read(appStateProvider).active!.entries[0].sets[0].done, isTrue);
    // Not the last set in the unit, so recovery starts.
    expect(ui.rest, isNotNull);
    expect(ui.rest!.total, 90);

    container.dispose();
  });

  testWidgets('finishing the last set asks for the working weight', (tester) async {
    final container = await pump(tester, running(exId: lift, sets: 1));

    await tester.ensureVisible(find.byType(AppCheck).first);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byType(AppCheck).first);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    // The top-weight sheet — the one number that carries forward to next session.
    expect(
        find.textContaining(
            'Confirm the weight you worked with — your highest becomes the default next time.'),
        findsOneWidget);

    container.dispose();
  });

  testWidgets('the effort column appears only when the profile logs one', (tester) async {
    final off = await pump(tester, running(exId: lift));
    expect(find.text('RIR'), findsNothing);
    off.dispose();

    final on = await pump(tester, running(exId: lift)..effort = 'rir');
    expect(find.text('RIR'), findsOneWidget);
    on.dispose();

    final rpe = await pump(tester, running(exId: lift)..effort = 'rpe');
    expect(find.text('RPE'), findsOneWidget);
    rpe.dispose();
  });

  testWidgets('a per-side exercise shows the split it plans', (tester) async {
    final s = running(exId: lift);
    s.active!.entries.first.target!
      ..side = true
      ..reps = 16;
    for (final set in s.active!.entries.first.sets) {
      set.r = 16;
    }
    final container = await pump(tester, s);
    // You log 16; the app says what that is per side.
    expect(find.text('8 per side'), findsOneWidget);
    container.dispose();
  });

  testWidgets('with no session the screen offers one to start', (tester) async {
    final routine = Routine(id: 'r', name: 'Push Day', ex: [ExerciseConfig(id: lift, sets: 3, reps: 8)]);
    final s = AppState.defaults()
      ..routines.add(routine)
      ..week['${jsDay(DateTime.now())}'] = 'r';
    final container = ProviderContainer();
    container.read(appStateProvider.notifier).replaceState(s);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyWellnessApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start').last);
    await tester.pumpAndSettle();

    // The weigh-in comes before the session, which is what keeps the curve honest.
    expect(find.text('Quick check-in'), findsOneWidget);
    expect(find.text('Save & start workout'), findsOneWidget);
    expect(find.text('Start without weighing in'), findsOneWidget);
    container.dispose();
  });
}
