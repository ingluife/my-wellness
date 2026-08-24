import 'package:flutter_test/flutter_test.dart';
import 'package:my_open_gym/data/models/app_state.dart';
import 'package:my_open_gym/domain/exercises.dart';
import 'package:my_open_gym/domain/history.dart';

import 'helpers.dart';

/// Ported from openGym/frontend/src/lib/history.test.js.
void main() {
  setUpAll(loadExercises);

  // Real ids out of the shipped catalogue, so the body-part fallback is exercised for real.
  late String cardio, lift, bw;

  setUpAll(() {
    cardio = exdb.db.firstWhere((e) => e.bp == 'cardio').id;
    // A *loaded* lift: the catalogue's first non-cardio entry is a sit-up, which defaults to
    // bodyweight and would quietly send every label test down the other path.
    lift = exdb.db.firstWhere((e) => e.bp != 'cardio' && e.eq != 'body weight').id;
    bw = exdb.db.firstWhere((e) => e.eq == 'body weight').id;
  });

  ExerciseConfig cfg({
    String? id,
    String? mode,
    double? sets,
    double? reps,
    double? weight,
    double? sec,
    double? min,
    double? speed,
    bool? bodyweight,
    bool? side,
  }) =>
      ExerciseConfig(
          id: id,
          mode: mode,
          sets: sets,
          reps: reps,
          weight: weight,
          sec: sec,
          min: min,
          speed: speed,
          bodyweight: bodyweight,
          side: side);

  group('modeOf', () {
    test('falls back to the body part when a plan has no mode', () {
      expect(modeOf(cfg(id: cardio)), 'cardio');
      expect(modeOf(cfg(id: lift)), 'reps');
      expect(modeOf(cfg(id: 'no-such-exercise')), 'reps');
      expect(modeOf(ExerciseConfig()), 'reps');
      expect(modeOf(null), 'reps');
    });

    test('lets an explicit mode win over the body part', () {
      expect(modeOf(cfg(id: lift, mode: 'time')), 'time');
      expect(modeOf(cfg(id: cardio, mode: 'reps')), 'reps');
      expect(modeOf(cfg(id: cardio, mode: 'time')), 'time');
    });

    test('ignores a mode it does not know rather than trusting a bad file', () {
      expect(modeOf(cfg(id: lift, mode: 'nonsense')), 'reps');
      expect(modeOf(cfg(id: cardio, mode: '')), 'cardio');
    });

    test('exposes the timed check', () {
      expect(isTimed(cfg(id: lift, mode: 'time')), isTrue);
      expect(isTimed(cfg(id: lift)), isFalse);
    });
  });

  group('fmtSec', () {
    test('reads as a clock, not a pile of seconds', () {
      expect(fmtSec(0), '0:00');
      expect(fmtSec(9), '0:09');
      expect(fmtSec(45), '0:45');
      expect(fmtSec(60), '1:00');
      expect(fmtSec(90), '1:30');
      expect(fmtSec(605), '10:05');
    });

    test('is defensive about junk input', () {
      expect(fmtSec(-5), '0:00');
      expect(fmtSec(null), '0:00');
      expect(fmtSec(44.6), '0:45');
    });
  });

  group('setLabel', () {
    test('describes each mode in its own terms', () {
      expect(setLabel(lift, SetLog(w: 60, r: 10)), '60×10');
      expect(setLabel(cardio, SetLog(min: 20, speed: 9)), '20 min @ 9 km/h');
      expect(setLabel(lift, SetLog(sec: 45, w: 0), cfg(mode: 'time')), '0:45');
      expect(setLabel(lift, SetLog(sec: 90, w: 20), cfg(mode: 'time')), '1:30 · 20');
    });

    test('reads a legacy set with no config exactly as before', () {
      expect(setLabel(lift, SetLog(w: 0, r: 0)), '0×0');
      expect(setLabel(cardio, SetLog()), '0 min @ 0 km/h');
    });

    test('appends RIR when present, including a valid 0', () {
      expect(setLabel(lift, SetLog(w: 60, r: 10, rir: 2)), '60×10 (RIR 2)');
      expect(setLabel(lift, SetLog(w: 60, r: 10, rir: 1.5)), '60×10 (RIR 1.5)');
      expect(setLabel(lift, SetLog(w: 60, r: 10, rir: 0)), '60×10 (RIR 0)');
    });

    test('says nothing about RIR on a set that never logged one', () {
      expect(setLabel(lift, SetLog(w: 60, r: 10)), '60×10');
      // Cleared in the UI: the key is dropped, and a null must read the same as absent.
      expect(setLabel(lift, SetLog(w: 60, r: 10, rir: null)), '60×10');
    });

    test('appends RPE for a set logged on that scale', () {
      expect(setLabel(lift, SetLog(w: 60, r: 10, rpe: 8)), '60×10 (RPE 8)');
      expect(setLabel(lift, SetLog(w: 60, r: 10, rpe: 9.5)), '60×10 (RPE 9.5)');
      expect(setLabel(lift, SetLog(w: 60, r: 10, rpe: null)), '60×10');
    });

    test('keeps each set on the scale it was logged with', () {
      expect(setLabel(lift, SetLog(w: 60, r: 10, rir: 2)), '60×10 (RIR 2)');
      // A set that somehow carries both is described once, by the one it was logged with.
      expect(setLabel(lift, SetLog(w: 60, r: 10, rir: 2, rpe: 8)), '60×10 (RIR 2)');
    });
  });

  group('effortOf', () {
    test('reads the scale a profile logs', () {
      expect(effortOf(AppState(effort: 'rpe')), 'rpe');
      expect(effortOf(AppState(effort: 'rir')), 'rir');
      expect(effortOf(AppState(effort: 'none')), 'none');
      expect(effortOf(AppState()), 'none');
    });

    test('keeps the column for a profile still carrying the old showRir flag', () {
      expect(effortOf(AppState(showRir: true)), 'rir');
      // What a stored profile actually looks like once it is overlaid on the defaults.
      expect(effortOf(AppState(effort: null, showRir: true)), 'rir');
      expect(effortOf(AppState(effort: null)), 'none');
      expect(effortOf(AppState(showRir: false)), 'none');
      // Once the new setting is chosen it wins, whatever the old flag said.
      expect(effortOf(AppState(showRir: true, effort: 'rpe')), 'rpe');
      expect(effortOf(AppState(showRir: true, effort: 'none')), 'none');
    });

    test('survives the overlay every load path performs', () {
      // Local state, a server pull and a restored backup all arrive as a stored object read
      // over the defaults, and all must keep the column. `effort` defaults to null precisely
      // so this lands on the showRir fallback rather than on 'none'.
      AppState overlay(Map<String, dynamic> stored) =>
          AppState.fromJson({'unit': 'kg', 'effort': null, ...stored});

      expect(effortOf(overlay({'showRir': true})), 'rir');
      expect(effortOf(overlay({'showRir': false})), 'none');
      // A profile predating the RIR feature entirely.
      expect(effortOf(overlay({})), 'none');
      // ...and one written by this version.
      expect(effortOf(overlay({'effort': 'rpe'})), 'rpe');
    });

    test('is not fooled by a junk value', () {
      expect(effortOf(AppState(effort: 'rpe10')), 'none');
      expect(effortOf(AppState(effort: 'RIR')), 'none');
      expect(effortOf(AppState(effort: 'f')), 'none');
      expect(effortOf(null), 'none');
      // A junk value with the old flag still set falls back rather than showing nothing.
      expect(effortOf(AppState(effort: 'nope', showRir: true)), 'rir');
    });
  });

  group('stepEffort', () {
    test('starts at the bottom of the scale and walks up', () {
      // The first + on an empty cell lands on the lowest value, not on some "typical" middle:
      // the stepper counts up from the floor the way every other stepper in the app does.
      expect(stepEffort('rir', null, 1), 0);
      expect(stepEffort('rpe', null, 1), 6);
      expect(stepEffort('rir', 0, 1), 0.5);
      expect(stepEffort('rir', 0.5, 1), 1);
      expect(stepEffort('rpe', 6, 1), 6.5);
    });

    test('leaves an untouched cell unlogged when stepped down', () {
      // One stray − on a fresh row must not stamp "(RIR 0)" — went to failure — on the set.
      expect(stepEffort('rir', null, -1), isNull);
      expect(stepEffort('rpe', null, -1), isNull);
    });

    test('clears the cell again when stepped back off the floor', () {
      // So a mistap is undoable rather than sticking at the floor for good.
      expect(stepEffort('rir', 0, -1), isNull);
      expect(stepEffort('rpe', 6, -1), isNull);
      // But a step that stays inside the scale is an ordinary step.
      expect(stepEffort('rir', 0.5, -1), 0);
      expect(stepEffort('rpe', 6.5, -1), 6);
    });

    test('stops at the top of the scale', () {
      expect(stepEffort('rir', 9.5, 1), 10);
      expect(stepEffort('rir', 10, 1), 10);
      expect(stepEffort('rpe', 10, 1), 10);
    });

    test('keeps halves clean instead of drifting into float dust', () {
      double? v;
      for (var i = 0; i < 6; i++) {
        v = stepEffort('rpe', v, 1);
      }
      expect(v, 8.5);
      expect(stepEffort('rir', 0.1 + 0.2, 1), 0.8);
    });

    test('steps evenly from a value typed below the floor rather than snapping', () {
      // Nothing stops someone typing RPE 3; the stepper must not jump them to 6 on one tap.
      expect(stepEffort('rpe', 3, 1), 3.5);
      // Stepping down out of the scale from there just clears it.
      expect(stepEffort('rpe', 3, -1), isNull);
    });

    test('does nothing when the profile logs no effort at all', () {
      expect(stepEffort('none', null, 1), isNull);
      expect(stepEffort('none', 2, 1), 2);
    });
  });

  group('capEffort', () {
    test('caps a typed value at the top of the scale', () {
      expect(capEffort('rir', 12), 10);
      expect(capEffort('rpe', 99), 10);
      expect(capEffort('rpe', 8), 8);
    });

    test('does not floor a typed value, so typing "10" survives its first keystroke', () {
      // Clamping up would turn the "1" of "10" into 6 and fight the input.
      expect(capEffort('rpe', 1), 1);
      expect(capEffort('rir', 0), 0);
    });

    test('passes an emptied field through untouched', () {
      expect(capEffort('rir', null), isNull);
      expect(capEffort('none', 12), 12);
    });
  });

  // End-to-end on the data, not the pixels: what a set carries after the taps a real session
  // makes, and what it reads back as afterwards.
  group('logging effort across a session', () {
    test('logs a working set on the chosen scale', () {
      // Four + taps from empty on an RPE profile: 6, 6.5, 7, 7.5.
      double? v;
      for (var i = 0; i < 4; i++) {
        v = stepEffort('rpe', v, 1);
      }
      expect(setLabel(lift, SetLog(w: 80, r: 5, rpe: v)), '80×5 (RPE 7.5)');
    });

    test('a set taken to failure is logged, not left blank', () {
      final v = stepEffort('rir', null, 1);
      expect(v, 0);
      expect(setLabel(lift, SetLog(w: 100, r: 3, rir: v)), '100×3 (RIR 0)');
    });

    test('switching the setting mid-history rewrites nothing', () {
      final old = SetLog(w: 60, r: 10, rir: 2); // logged while the profile was on RIR
      final fresh = SetLog(w: 60, r: 10, rpe: 8); // logged after switching to RPE
      expect(effortOf(AppState(effort: 'rpe')), 'rpe');
      expect(setLabel(lift, old), '60×10 (RIR 2)');
      expect(setLabel(lift, fresh), '60×10 (RPE 8)');
      // Turning the column off entirely hides the control but keeps both sets readable.
      expect(effortOf(AppState(effort: 'none')), 'none');
      expect(setLabel(lift, old), '60×10 (RIR 2)');
    });

    test('never attaches effort to a mode that has no place for it', () {
      // Cardio and timed sets have no third stepper, and their labels ignore the field even
      // if an import or an old file put one there.
      expect(setLabel(cardio, SetLog(min: 20, speed: 9, rpe: 8)), '20 min @ 9 km/h');
      expect(setLabel(lift, SetLog(sec: 45, rir: 2), cfg(id: lift, mode: 'time')), '0:45');
    });
  });

  group('defaultConfig', () {
    test('gives each mode a sensible starting point', () {
      expect(defaultConfig(lift).toJson(),
          {'id': lift, 'sets': 3, 'reps': 10, 'weight': 0, 'mode': 'reps'});
      expect(defaultConfig(cardio).toJson(), {'id': cardio, 'sets': 1, 'min': 20, 'speed': 8});
      expect(defaultConfig(lift, 'time').toJson(),
          {'id': lift, 'sets': 3, 'weight': 0, 'mode': 'time', 'sec': 45});
    });

    test('seeds the bodyweight flag from the catalogue, and only when it is true', () {
      expect(defaultConfig(bw).toJson()['bodyweight'], isTrue);
      expect(defaultConfig(bw, 'time').toJson()['bodyweight'], isTrue);
      expect(defaultConfig(lift).toJson().containsKey('bodyweight'), isFalse);
    });
  });

  group('isBw', () {
    test('defaults from the catalogue so an existing plan needs no flag', () {
      expect(isBw(cfg(id: bw)), isTrue);
      expect(isBw(cfg(id: lift)), isFalse);
    });

    test('lets the config win in both directions — a belt on a dip, a flag on a machine', () {
      expect(isBw(cfg(id: bw, bodyweight: false)), isFalse);
      expect(isBw(cfg(id: lift, bodyweight: true)), isTrue);
    });
  });

  group('sideReps', () {
    test('halves the logged total, because the total is what was logged', () {
      expect(sideReps(16), 8);
      expect(sideReps(0), 0);
    });

    test('shows an odd total as it falls rather than rounding the imbalance away', () {
      expect(sideReps(17), 8.5);
    });
  });

  group('repStep', () {
    test('steps unilateral work in twos so the total stays splittable', () {
      expect(repStep(cfg(side: true)), 2);
      expect(repStep(ExerciseConfig()), 1);
      expect(repStep(null), 1);
    });
  });

  group('setLabel — bodyweight', () {
    test('reads as reps alone, because "0×12" describes nothing', () {
      expect(setLabel(bw, SetLog(w: 0, r: 12), cfg(id: bw)), '12');
    });

    test('spells out a belt as an addition', () {
      expect(setLabel(bw, SetLog(w: 10, r: 8), cfg(id: bw)), '+10 × 8');
    });

    test('logs a per-side set as the plain total, like every other set in the app', () {
      expect(setLabel(bw, SetLog(w: 0, r: 16), cfg(id: bw, side: true)), '16');
      expect(setLabel(lift, SetLog(w: 20, r: 16), cfg(id: lift, side: true)), '20×16');
    });

    test('keeps the effort tail', () {
      expect(setLabel(bw, SetLog(w: 0, r: 12, rir: 2), cfg(id: bw)), '12 (RIR 2)');
    });
  });

  group('exLine', () {
    test('ignores a stale side flag on a hold, which has no reps to split', () {
      expect(exLine(cfg(id: lift, sets: 3, sec: 45, mode: 'time', side: true), 'kg'), '3 × 0:45');
    });

    test('shows the split where there is room for it, next to the total you log', () {
      expect(exLine(cfg(id: lift, sets: 3, reps: 16, side: true), 'kg'), '3 × 16 · 8/side');
    });

    test('marks added weight as added', () {
      expect(exLine(cfg(id: bw, sets: 3, reps: 8, weight: 10), 'kg'), '3 × 8 · +10 kg');
    });

    test('summarises a planned exercise per mode', () {
      expect(exLine(cfg(id: lift, sets: 3, reps: 10), 'kg'), '3 × 10');
      expect(exLine(cfg(id: lift, sets: 3, reps: 10, weight: 60), 'kg'), '3 × 10 · 60 kg');
      expect(exLine(cfg(id: lift, sets: 3, sec: 45, mode: 'time'), 'kg'), '3 × 0:45');
      expect(exLine(cfg(id: lift, sets: 2, sec: 90, weight: 20, mode: 'time'), 'kg'),
          '2 × 1:30 · 20 kg');
      expect(exLine(cfg(id: cardio, sets: 1, min: 20, speed: 8), 'kg'), '1 × 20 min @ 8 km/h');
    });
  });

  group('buildSets', () {
    AppState empty() => AppState();

    List<Map<String, dynamic>> json(List<SetLog> sets) => [for (final s in sets) s.toJson()];

    test('builds reps sets from the plan when there is no history', () {
      expect(json(buildSets(empty(), cfg(id: lift, sets: 3, reps: 8, weight: 50))), [
        {'w': 50, 'r': 8, 'done': false},
        {'w': 50, 'r': 8, 'done': false},
        {'w': 50, 'r': 8, 'done': false},
      ]);
    });

    test('builds timed sets, carrying the planned duration and load', () {
      expect(json(buildSets(empty(), cfg(id: lift, mode: 'time', sets: 2, sec: 60, weight: 20))), [
        {'w': 20, 'sec': 60, 'done': false},
        {'w': 20, 'sec': 60, 'done': false},
      ]);
    });

    test('builds cardio sets unchanged', () {
      expect(json(buildSets(empty(), cfg(id: cardio, sets: 1, min: 25, speed: 9))), [
        {'min': 25, 'speed': 9, 'done': false}
      ]);
    });

    test("carries last time's numbers forward within the same mode", () {
      final s = AppState(workouts: [
        wk('2026-01-01', [
          WorkoutEntry(
              id: lift,
              target: ExerciseConfig(mode: 'time'),
              sets: [SetLog(sec: 70, w: 10, done: true)])
        ])
      ]);
      expect(json(buildSets(s, cfg(id: lift, mode: 'time', sets: 2, sec: 45, weight: 0))), [
        {'w': 10, 'sec': 70, 'done': false},
        {'w': 10, 'sec': 70, 'done': false},
      ]);
    });

    test('does not seed a duration from a rep count when an exercise switches to time', () {
      final s = AppState(workouts: [
        wk('2026-01-01', [WorkoutEntry(id: lift, sets: [SetLog(w: 60, r: 10, done: true)])])
      ]);
      expect(json(buildSets(s, cfg(id: lift, mode: 'time', sets: 1, sec: 45, weight: 0))), [
        {'w': 0, 'sec': 45, 'done': false}
      ]);
    });

    test('does not seed reps from a timed set when an exercise switches back', () {
      final s = AppState(workouts: [
        wk('2026-01-01', [
          WorkoutEntry(
              id: lift,
              target: ExerciseConfig(mode: 'time'),
              sets: [SetLog(sec: 70, w: 10, done: true)])
        ])
      ]);
      expect(json(buildSets(s, cfg(id: lift, mode: 'reps', sets: 1, reps: 8, weight: 40))), [
        {'w': 40, 'r': 8, 'done': false}
      ]);
    });

    test('still prefers the confirmed working weight for reps sets', () {
      final s = AppState(
        exWeights: {lift: ExWeight(w: 75, d: '2026-01-01')},
        workouts: [
          wk('2026-01-01', [WorkoutEntry(id: lift, sets: [SetLog(w: 60, r: 10, done: true)])])
        ],
      );
      expect(json(buildSets(s, cfg(id: lift, sets: 1, reps: 8, weight: 50))), [
        {'w': 75, 'r': 10, 'done': false}
      ]);
    });
  });

  group('workoutVolume', () {
    test('counts reps work and leaves timed/cardio sets out', () {
      final w = wk('2026-01-01', [
        WorkoutEntry(id: lift, sets: [
          SetLog(w: 60, r: 10, done: true),
          SetLog(w: 60, r: 10, done: false),
        ]),
        WorkoutEntry(
            id: lift,
            target: ExerciseConfig(mode: 'time'),
            sets: [SetLog(sec: 60, w: 20, done: true)]),
        WorkoutEntry(id: cardio, sets: [SetLog(min: 20, speed: 9, done: true)]),
      ]);
      expect(workoutVolume(w), 600);
    });

    test('needs no per-side case — the logged reps are already both sides', () {
      final w = wk('2026-01-01', [
        WorkoutEntry(
            id: lift,
            target: ExerciseConfig(side: true),
            sets: [SetLog(w: 20, r: 16, done: true)])
      ]);
      expect(workoutVolume(w), 320);
    });

    test('leaves an unloaded bodyweight set at zero volume rather than inventing a number', () {
      final w = wk('2026-01-01', [
        WorkoutEntry(
            id: bw,
            target: ExerciseConfig(bodyweight: true),
            sets: [SetLog(w: 0, r: 20, done: true)])
      ]);
      expect(workoutVolume(w), 0);
    });
  });
}
