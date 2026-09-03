import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/exercises.dart';
import 'package:my_wellness/domain/progression.dart';

/// Loads the real bundled dataset, so the logic tests run against the same 1,324 exercises the
/// app does — body parts drive the load increment, and equipment drives the bodyweight flag.
Future<void> loadExercises() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await exdb.load();
}

/// A finished workout holding [entries], for tests that only care about the sets in it.
Workout wk(String d, List<WorkoutEntry> entries) =>
    Workout(id: 'w-$d', d: d, start: 0, end: 0, name: '', entries: entries);

/// A [Session] that is only ever inspected for `ok` — what `stallCount` reads.
Session okSession(bool ok) => (
      d: '',
      mode: 'reps',
      goal: 5,
      reps: const [],
      held: const [],
      weight: 0,
      count: 0,
      low: 0,
      amrap: 0,
      best: 0,
      ok: ok,
    );
