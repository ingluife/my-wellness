import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/exercises.dart';
import 'package:my_wellness/domain/format.dart';
import 'package:my_wellness/state/app_state_provider.dart';
import 'package:my_wellness/ui/app.dart';
import 'package:my_wellness/ui/widgets/body_map.dart';
import 'package:my_wellness/ui/widgets/heatmap.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting();
    await Exercises.instance.load();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  late String lift;
  setUpAll(() =>
      lift = Exercises.instance.db.firstWhere((e) => e.bp != 'cardio' && e.eq == 'barbell').id);

  Future<ProviderContainer> open(WidgetTester tester, AppState s) async {
    final container = ProviderContainer();
    container.read(appStateProvider.notifier).replaceState(s);
    await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyWellnessApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stats').last);
    await tester.pumpAndSettle();
    return container;
  }

  Workout session(String d, {List<SetLog>? sets, List<String>? prs}) => Workout(
        id: 'w-$d',
        d: d,
        start: dayOf(d).millisecondsSinceEpoch,
        end: dayOf(d).millisecondsSinceEpoch + 3600000,
        name: 'Push Day',
        vol: 7535,
        prs: prs ?? [],
        entries: [
          WorkoutEntry(
            id: lift,
            target: ExerciseConfig(sets: 3, reps: 8, weight: 60, mode: 'reps'),
            sets: sets ??
                [
                  SetLog(w: 60, r: 8, done: true),
                  SetLog(w: 62.5, r: 8, done: true),
                ],
          )
        ],
      );

  testWidgets('an untrained profile shows the tiles and the heatmap, and nothing it cannot',
      (tester) async {
    final container = await open(tester, AppState.defaults());
    expect(find.text('Stats'), findsWidgets);
    expect(find.byType(Heatmap), findsOneWidget);
    expect(find.text('Workouts'), findsOneWidget);
    // No training means no muscle map and no effort card to draw.
    expect(find.byType(BodyMap), findsNothing);
    expect(find.textContaining('Effort ·', findRichText: true), findsNothing);
    expect(find.text('Finish your first workout to see progress curves here.'), findsOneWidget);
    container.dispose();
  });

  testWidgets('training brings in the muscle balance card', (tester) async {
    final container =
        await open(tester, AppState.defaults()..workouts.add(session(todayISO())));
    expect(find.textContaining('Muscle balance', findRichText: true), findsOneWidget);
    expect(find.byType(BodyMap), findsOneWidget);
    // Default window is the current week.
    expect(find.text('Week'), findsOneWidget);
    container.dispose();
  });

  testWidgets('the effort card appears only once something was rated', (tester) async {
    final unrated =
        await open(tester, AppState.defaults()..workouts.add(session(todayISO())));
    expect(find.textContaining('Effort ·', findRichText: true), findsNothing);
    unrated.dispose();

    final rated = await open(
      tester,
      AppState.defaults()
        ..effort = 'rir'
        ..workouts.add(session(todayISO(), sets: [
          SetLog(w: 60, r: 8, done: true, rir: 2),
          SetLog(w: 60, r: 8, done: true, rir: 1),
        ])),
    );
    expect(find.textContaining('Effort ·', findRichText: true), findsOneWidget);
    expect(find.textContaining('2 of 2 finished sets rated'), findsOneWidget);
    rated.dispose();
  });

  testWidgets('a PR is carried through to the recent-workout list', (tester) async {
    final container = await open(
      tester,
      AppState.defaults()..workouts.add(session(todayISO(), prs: [lift])),
    );
    expect(find.text('Recent workouts'), findsOneWidget);
    expect(find.text('1 PR'), findsOneWidget);
    container.dispose();
  });

  testWidgets('the exercise progress card names what the curve means', (tester) async {
    final container =
        await open(tester, AppState.defaults()..workouts.add(session(todayISO())));
    expect(find.text('Exercise progress', findRichText: true), findsOneWidget);
    expect(find.textContaining('Best set weight per workout'), findsOneWidget);
    container.dispose();
  });

  testWidgets('history is reachable and lists every session', (tester) async {
    final container = await open(
      tester,
      AppState.defaults()
        ..workouts.addAll([session('2026-08-20'), session('2026-08-22')]),
    );
    await tester.ensureVisible(find.text('All 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All 2'));
    await tester.pumpAndSettle();
    expect(find.text('History'), findsOneWidget);
    expect(find.text('2 workouts'), findsOneWidget);
    container.dispose();
  });
}
