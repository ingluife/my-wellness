import '../data/models/app_state.dart';
import 'format.dart';

/// The Push/Pull/Legs starter plan, from lib/starter.js — the "Load starter plan" action in
/// Home and Settings. Exercise ids are the dataset's, so the routines arrive with animations
/// and instructions already attached.
const _spec = <({String name, String emoji, List<List<Object>> ex})>[
  (name: 'Push Day', emoji: 'barbell', ex: [
    ['0025', 4, 8], ['0047', 3, 10], ['0426', 3, 10],
    ['0334', 3, 12], ['0241', 3, 12], ['0251', 3, 10],
  ]),
  (name: 'Pull Day', emoji: 'pullup', ex: [
    ['2330', 4, 10], ['0027', 4, 8], ['1323', 3, 10], ['0031', 3, 10], ['0313', 3, 12],
  ]),
  (name: 'Leg Day', emoji: 'legs', ex: [
    ['0043', 4, 8], ['0085', 3, 10], ['0739', 3, 12],
    ['0585', 3, 12], ['0586', 3, 12], ['0605', 4, 15],
  ]),
];

/// Fresh routine objects with new ids — [push, pull, legs].
List<Routine> starterRoutines() => [
      for (final r in _spec)
        Routine(
          id: uid(),
          name: r.name,
          emoji: r.emoji,
          ex: [
            for (final e in r.ex)
              ExerciseConfig(
                id: e[0] as String,
                sets: (e[1] as int).toDouble(),
                reps: (e[2] as int).toDouble(),
                weight: 0,
              )
          ],
        )
    ];
