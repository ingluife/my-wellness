import 'exercise_config.dart';
import 'json.dart';

/// A named training day: an icon, an ordered list of exercises, and optionally a progression
/// rule every exercise in it inherits unless it sets its own.
class Routine {
  Routine({required this.id, required this.name, this.emoji, this.prog, List<ExerciseConfig>? ex})
      : ex = ex ?? [];

  final String id;
  String name;

  /// The field is still called `emoji` although it now stores an icon key ('barbell',
  /// 'pullup', ...). Keeping the name means state synced by either build stays readable by
  /// both — no migration, no lost routines. `glyphOf()` accepts either form.
  String? emoji;

  /// Routine-level progression policy; an exercise's own `prog` wins over it.
  String? prog;

  List<ExerciseConfig> ex;

  factory Routine.fromJson(Map<String, dynamic> j) => Routine(
        id: asStr(j['id']) ?? '',
        name: asStr(j['name']) ?? '',
        emoji: asStr(j['emoji']),
        prog: asStr(j['prog']),
        ex: asList(j['ex'], ExerciseConfig.fromJson),
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{'id': id, 'name': name};
    put(m, 'emoji', emoji);
    put(m, 'prog', prog);
    m['ex'] = [for (final e in ex) e.toJson()];
    return m;
  }

  Routine copy() => Routine.fromJson(toJson());
}
