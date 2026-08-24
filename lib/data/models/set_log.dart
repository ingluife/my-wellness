import 'json.dart';

/// One logged set.
///
/// Three shapes live in this class because three shapes live in the same array in the source
/// — which shape applies is decided by `modeOf(cfg)` on the *config*, not by the set:
///
///   reps    `{ w, r, done }`      weight x reps (+ an optional rir/rpe rating)
///   time    `{ sec, w, done }`    a held duration; `w` is 0 for a bodyweight hold
///   cardio  `{ min, speed, done }`
///
/// Fields outside the active mode stay null and are never written, so a set on disk carries
/// exactly what a JS set carries. `rir` and `rpe` are separate fields on purpose: a set is
/// never silently rewritten into the other scale (see history.js).
class SetLog {
  SetLog({this.w, this.r, this.sec, this.min, this.speed, this.done = false, this.rir, this.rpe});

  double? w;
  double? r;
  double? sec;
  double? min;
  double? speed;
  bool done;
  double? rir;
  double? rpe;

  factory SetLog.fromJson(Map<String, dynamic> j) => SetLog(
        w: asNum(j['w']),
        r: asNum(j['r']),
        sec: asNum(j['sec']),
        min: asNum(j['min']),
        speed: asNum(j['speed']),
        done: asBool(j['done']),
        rir: asNum(j['rir']),
        rpe: asNum(j['rpe']),
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    putNum(m, 'w', w);
    putNum(m, 'r', r);
    putNum(m, 'sec', sec);
    putNum(m, 'min', min);
    putNum(m, 'speed', speed);
    m['done'] = done;
    putNum(m, 'rir', rir);
    putNum(m, 'rpe', rpe);
    return m;
  }

  SetLog copy() => SetLog.fromJson(toJson());

  /// Reads one of the numeric columns by its field name, the way the workout view's
  /// `s[col.f]` does.
  double? field(String f) => switch (f) {
        'w' => w,
        'r' => r,
        'sec' => sec,
        'min' => min,
        'speed' => speed,
        'rir' => rir,
        'rpe' => rpe,
        _ => null,
      };

  /// Writes one column. A null clears it — dropping the key rather than storing a null, so a
  /// cleared effort reads back as "never rated".
  void setField(String f, double? v) {
    switch (f) {
      case 'w': w = v;
      case 'r': r = v;
      case 'sec': sec = v;
      case 'min': min = v;
      case 'speed': speed = v;
      case 'rir': rir = v;
      case 'rpe': rpe = v;
    }
  }
}
