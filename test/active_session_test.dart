import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/format.dart';
import 'package:my_wellness/state/active_session.dart';
import 'package:my_wellness/state/sound.dart';
import 'package:my_wellness/state/ui_provider.dart';

/// Records what it was asked to play instead of touching an audio route — see
/// test/ui_controller_test.dart, which this mirrors.
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

/// A minimal in-place store: `ActiveSession` only needs a read and an update, not the deep
/// clone the real `AppStateController` does around every mutation.
class _Store {
  _Store(this.state);
  AppState state;
  AppState read() => state;
  void update(void Function(AppState s) mutate) => mutate(state);
}

void main() {
  /// Two entries, two sets each, back to back with no superset grouping — one exercise's unit
  /// finishing does not touch the other's.
  AppState twoExercises({bool asSuperset = false}) => AppState.defaults()
    ..active = ActiveWorkout(
      id: 'a',
      d: todayISO(),
      start: 0,
      name: 'Push Day',
      entries: [
        WorkoutEntry(
          id: 'bench',
          sg: asSuperset ? 'sg1' : null,
          target: ExerciseConfig(id: 'bench', mode: 'reps', weight: 60, reps: 8),
          sets: [SetLog(w: 60, r: 8), SetLog(w: 60, r: 8)],
        ),
        WorkoutEntry(
          id: 'row',
          sg: asSuperset ? 'sg1' : null,
          target: ExerciseConfig(id: 'row', mode: 'reps', weight: 40, reps: 10),
          sets: [SetLog(w: 40, r: 10), SetLog(w: 40, r: 10)],
        ),
      ],
    );

  ({ActiveSession session, _Store store, UiController ui}) rig(AppState initial) {
    final store = _Store(initial);
    final ui = UiController(sound: _FakeSound());
    final session =
        ActiveSession(read: store.read, update: store.update, ui: ui);
    return (session: session, store: store, ui: ui);
  }

  group('focus', () {
    test('the first unmarked set of the first entry with work left', () {
      final r = rig(twoExercises());
      expect(r.session.focus(r.store.state), (entry: 0, set: 0));
    });

    test('skips a finished entry and lands on the next one with work left', () {
      final s = twoExercises();
      for (final set in s.active!.entries[0].sets) {
        set.done = true;
      }
      final r = rig(s);
      expect(r.session.focus(r.store.state), (entry: 1, set: 0));
    });

    test('skips a done set within an entry, not just done entries', () {
      final s = twoExercises();
      s.active!.entries[0].sets[0].done = true;
      final r = rig(s);
      expect(r.session.focus(r.store.state), (entry: 0, set: 1));
    });

    test('wraps around from active.cur instead of always starting at 0', () {
      final s = twoExercises();
      s.active!.cur = 1;
      final r = rig(s);
      expect(r.session.focus(r.store.state), (entry: 1, set: 0));
    });

    test('null once every set in the session is done', () {
      final s = twoExercises();
      for (final e in s.active!.entries) {
        for (final set in e.sets) {
          set.done = true;
        }
      }
      final r = rig(s);
      expect(r.session.focus(r.store.state), isNull);
    });

    test('null with no active session', () {
      final r = rig(AppState.defaults());
      expect(r.session.focus(r.store.state), isNull);
    });
  });

  group('adjust', () {
    test('adds the delta to the named column', () {
      final r = rig(twoExercises());
      r.session.adjust(0, 0, 'r', 1);
      expect(r.store.state.active!.entries[0].sets[0].r, 9);
      r.session.adjust(0, 0, 'w', 2.5);
      expect(r.store.state.active!.entries[0].sets[0].w, 62.5);
    });

    test('floors at 0 rather than going negative', () {
      final r = rig(twoExercises());
      r.session.adjust(0, 0, 'r', -100);
      expect(r.store.state.active!.entries[0].sets[0].r, 0);
    });

    test('starts from 0 when the field was never set', () {
      final r = rig(twoExercises());
      r.session.adjust(0, 0, 'rir', 0.5);
      expect(r.store.state.active!.entries[0].sets[0].rir, 0.5);
    });
  });

  group('toggle', () {
    test('null with no active session', () {
      final r = rig(AppState.defaults());
      expect(r.session.toggle(0, 0), isNull);
    });

    test('checking a set that does not finish the exercise starts the rest timer', () {
      final r = rig(twoExercises());
      final result = r.session.toggle(0, 0);
      expect(result, (
        entryIndex: 0,
        askTopWeight: false,
        exerciseDone: false,
        workoutDone: false,
        mode: 'reps',
      ));
      expect(r.ui.rest, isNotNull);
      expect(r.store.state.active!.entries[0].sets[0].done, isTrue);
    });

    test('finishing an exercise that is not the last unit stops any rest and asks for the '
        'working weight', () {
      final r = rig(twoExercises());
      r.session.toggle(0, 0);
      final result = r.session.toggle(0, 1);
      expect(result!.exerciseDone, isTrue);
      expect(result.askTopWeight, isTrue);
      expect(result.workoutDone, isFalse);
      expect(r.ui.rest, isNull);
    });

    test('finishing the last unit reports workoutDone and does not start a rest timer', () {
      final r = rig(twoExercises());
      r.session.toggle(0, 0);
      r.session.toggle(0, 1);
      r.session.toggle(1, 0);
      final result = r.session.toggle(1, 1);
      expect(result!.workoutDone, isTrue);
      expect(r.ui.rest, isNull);
    });

    test('a superset only rests after the last exercise in the unit, not every one', () {
      final r = rig(twoExercises(asSuperset: true));
      r.session.toggle(0, 0);
      r.session.toggle(0, 1);
      // Bench is done, but the unit is not — row still has work left, so no rest yet.
      expect(r.ui.rest, isNull);
      r.session.toggle(1, 0);
      final result = r.session.toggle(1, 1);
      expect(result!.workoutDone, isTrue);
    });

    test('a bodyweight exercise with nothing added never asks for a working weight', () {
      final s = AppState.defaults()
        ..active = ActiveWorkout(
          id: 'a',
          d: todayISO(),
          start: 0,
          name: 'Push Day',
          entries: [
            WorkoutEntry(
              id: 'pushup',
              target: ExerciseConfig(id: 'pushup', mode: 'reps', bodyweight: true, reps: 12),
              sets: [SetLog(w: 0, r: 12)],
            ),
          ],
        );
      final r = rig(s);
      final result = r.session.toggle(0, 0);
      expect(result!.exerciseDone, isTrue);
      expect(result.askTopWeight, isFalse);
    });

    test('un-checking a set reports no follow-up and triggers no side effect', () {
      final r = rig(twoExercises());
      r.session.toggle(0, 0);
      final result = r.session.toggle(0, 0);
      expect(result, (
        entryIndex: 0,
        askTopWeight: false,
        exerciseDone: false,
        workoutDone: false,
        mode: 'reps',
      ));
      expect(r.store.state.active!.entries[0].sets[0].done, isFalse);
    });
  });
}
