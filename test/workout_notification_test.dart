import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/exercises.dart';
import 'package:my_wellness/domain/format.dart';
import 'package:my_wellness/platform/workout_notification.dart';
import 'package:my_wellness/state/active_session.dart';
import 'package:my_wellness/state/sound.dart';
import 'package:my_wellness/state/ui_provider.dart';

class _FakeSound implements Sound {
  @override
  void countdown(bool enabled) {}
  @override
  void setDone(bool enabled) {}
  @override
  void restOver(bool enabled) {}
  @override
  void workoutDone(bool enabled) {}
  @override
  void tap() {}
  @override
  void dispose() {}
  @override
  noSuchMethod(Invocation i) => null;
}

/// `render` only ever calls `ActiveSession.focus`, so the session here need not mutate
/// anything — the read is enough.
ActiveSession sessionOver(AppState s) => ActiveSession(
      read: () => s,
      update: (_) => throw UnimplementedError('render does not mutate'),
      ui: UiController(sound: _FakeSound()),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Exercises.instance.load();
  });

  late String lift, bw, cardio;
  setUpAll(() {
    lift = Exercises.instance.db.firstWhere((e) => e.bp != 'cardio' && e.eq == 'barbell').id;
    bw = Exercises.instance.db.firstWhere((e) => e.eq == 'body weight').id;
    cardio = Exercises.instance.db.firstWhere((e) => e.bp == 'cardio').id;
  });

  AppState withEntry(WorkoutEntry entry) => AppState.defaults()
    ..active = ActiveWorkout(id: 'a', d: todayISO(), start: 0, name: 'Push Day', entries: [entry]);

  test('null with no active session', () {
    final s = AppState.defaults();
    expect(render(s, sessionOver(s), swap: false), isNull);
  });

  test('a loaded lift shows weight first, and swap switches to reps', () {
    final s = withEntry(WorkoutEntry(
      id: lift,
      target: ExerciseConfig(id: lift, mode: 'reps', weight: 60, reps: 8),
      sets: [SetLog(w: 60, r: 8), SetLog(w: 60, r: 8)],
    ));
    final session = sessionOver(s);

    final unswapped = render(s, session, swap: false)!;
    expect(unswapped.title, contains('Set 1/2'));
    expect(unswapped.body, '60×8');
    expect(unswapped.canSwap, isTrue);
    expect(unswapped.minusLabel, '−2.5');
    expect(unswapped.plusLabel, '+2.5');

    final swapped = render(s, session, swap: true)!;
    expect(swapped.minusLabel, '−1');
    expect(swapped.plusLabel, '+1');
  });

  test('the set position advances once the first set is done', () {
    final s = withEntry(WorkoutEntry(
      id: lift,
      target: ExerciseConfig(id: lift, mode: 'reps', weight: 60, reps: 8),
      sets: [SetLog(w: 60, r: 8, done: true), SetLog(w: 60, r: 8)],
    ));
    final model = render(s, sessionOver(s), swap: false)!;
    expect(model.title, contains('Set 2/2'));
  });

  test('a bodyweight set with nothing added has no second column, and swap is a no-op', () {
    final s = withEntry(WorkoutEntry(
      id: bw,
      target: ExerciseConfig(id: bw, mode: 'reps', bodyweight: true, reps: 12),
      sets: [SetLog(w: 0, r: 12)],
    ));
    final session = sessionOver(s);
    final unswapped = render(s, session, swap: false)!;
    final swapped = render(s, session, swap: true)!;
    expect(unswapped.canSwap, isFalse);
    expect(unswapped.sub, isEmpty);
    // Nothing to switch to, so both flags render the same reps stepper.
    expect(unswapped.minusLabel, swapped.minusLabel);
    expect(unswapped.plusLabel, swapped.plusLabel);
  });

  test('a cardio entry steps duration and, once swapped, speed', () {
    final s = withEntry(WorkoutEntry(
      id: cardio,
      target: ExerciseConfig(id: cardio, mode: 'cardio', min: 20, speed: 8),
      sets: [SetLog(min: 20, speed: 8)],
    ));
    final session = sessionOver(s);
    expect(render(s, session, swap: false)!.minusLabel, '−1');
    expect(render(s, session, swap: true)!.minusLabel, '−0.5');
  });

  test('a timed hold steps seconds', () {
    final s = withEntry(WorkoutEntry(
      id: lift,
      target: ExerciseConfig(id: lift, mode: 'time', sec: 45, weight: 0),
      sets: [SetLog(sec: 45, w: 0)],
    ));
    final model = render(s, sessionOver(s), swap: false)!;
    expect(model.minusLabel, '−5');
  });

  test('every set logged, session still open: no stepper labels, but still something to show',
      () {
    final s = withEntry(WorkoutEntry(
      id: lift,
      target: ExerciseConfig(id: lift, mode: 'reps', weight: 60, reps: 8),
      sets: [SetLog(w: 60, r: 8, done: true)],
    ));
    final model = render(s, sessionOver(s), swap: false)!;
    expect(model.canSwap, isFalse);
    expect(model.minusLabel, isEmpty);
  });

  test('two renders of the same session are equal, so sync can skip an unchanged redraw', () {
    final s = withEntry(WorkoutEntry(
      id: lift,
      target: ExerciseConfig(id: lift, mode: 'reps', weight: 60, reps: 8),
      sets: [SetLog(w: 60, r: 8)],
    ));
    final session = sessionOver(s);
    expect(render(s, session, swap: false), render(s, session, swap: false));
  });

  group('sync', () {
    test('does not call the platform channel when the feature is off', () async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('com.mywellness.app/workout_notification');
      TestWidgetsFlutterBinding.ensureInitialized();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      final s = withEntry(WorkoutEntry(
        id: lift,
        target: ExerciseConfig(id: lift, mode: 'reps', weight: 60, reps: 8),
        sets: [SetLog(w: 60, r: 8)],
      ))
        ..workoutNotif = false;

      final notif = WorkoutNotification.instance;
      notif.bind(sessionOver(s), UiController(sound: _FakeSound()), () => s);
      await notif.sync(s);
      expect(calls, isEmpty);
    });
  });
}
