import 'json.dart';

/// What the progression engine decided for one exercise this session, and why.
///
/// Kept on the workout entry purely so the session can explain the number it opened with —
/// nothing reads it back. `why` is a translatable template plus its arguments rather than a
/// finished sentence, so the reason is shown in the profile's language, not the language it
/// was computed in.
class Prescription {
  Prescription({this.policy, this.kind, this.weight, this.reps, this.sec, this.sets, this.why});

  /// 'off' | 'linear' | 'greyskull' | 'double' | 'time'
  String? policy;

  /// 'first' | 'up' | 'hold' | 'deload' | 'off'
  String? kind;

  /// Only the fields the policy actually had an opinion on are set; the caller keeps whatever
  /// the plan said for the rest.
  double? weight;
  double? reps;
  double? sec;
  double? sets;

  /// `[template, ...args]`
  List<Object?>? why;

  factory Prescription.fromJson(Map<String, dynamic> j) => Prescription(
        policy: asStr(j['policy']),
        kind: asStr(j['kind']),
        weight: asNum(j['weight']),
        reps: asNum(j['reps']),
        sec: asNum(j['sec']),
        sets: asNum(j['sets']),
        why: j['why'] is List ? List<Object?>.from(j['why'] as List) : null,
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    put(m, 'policy', policy);
    put(m, 'kind', kind);
    putNum(m, 'weight', weight);
    putNum(m, 'reps', reps);
    putNum(m, 'sec', sec);
    putNum(m, 'sets', sets);
    if (why != null) m['why'] = [for (final a in why!) a is num ? jsonNum(a) : a];
    return m;
  }

  Prescription copy() => Prescription.fromJson(toJson());
}
