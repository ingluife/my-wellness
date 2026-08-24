/// Helpers that keep the Dart models writing the *same* JSON the JavaScript ones do.
///
/// Two rules matter for backup interchange with openGym:
///
///  1. An unset optional field is **absent**, never `null`. `setField` in Workout.jsx deletes
///     the key rather than storing null, precisely so a set only carries what was actually
///     logged — an absent `rir` means unrated, and a written `null` would be a third state
///     nothing downstream knows how to read.
///  2. A whole number serialises as an integer. JS has one number type, so `JSON.stringify`
///     writes `"r":8`; Dart would write `"r":8.0` for the same value. Both parse back
///     identically, but keeping the textual form means a diff of two backups shows real
///     changes rather than formatting.
library;

/// Writes [value] under [key] only when it is set.
void put(Map<String, dynamic> m, String key, Object? value) {
  if (value != null) m[key] = value;
}

/// As [put], but collapses an integral double to an int first.
void putNum(Map<String, dynamic> m, String key, num? value) {
  if (value != null) m[key] = jsonNum(value);
}

/// Emits `8` for 8.0 and `8.5` for 8.5 — see rule 2 above.
num jsonNum(num v) {
  if (v is int) return v;
  final d = v.toDouble();
  return d == d.roundToDouble() && d.isFinite ? d.toInt() : d;
}

/// Reads a number that may arrive as int, double or a numeric string.
double? asNum(Object? v) => switch (v) {
      null => null,
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };

double asNumOr(Object? v, double fallback) => asNum(v) ?? fallback;

/// JS truthiness is not Dart's, but every boolean in the state is stored as a real boolean
/// or absent, so absent-is-false is the whole rule.
bool asBool(Object? v, {bool fallback = false}) => v is bool ? v : fallback;

String? asStr(Object? v) => v is String ? v : null;

List<T> asList<T>(Object? v, T Function(Map<String, dynamic>) fromJson) =>
    v is List
        ? [for (final e in v) if (e is Map) fromJson(Map<String, dynamic>.from(e))]
        : <T>[];

Map<String, dynamic> asMap(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

/// Deep copy through JSON, the Dart spelling of `JSON.parse(JSON.stringify(o))` — the clone
/// every `update()` in useStore.js takes before handing a draft to its producer.
Map<String, dynamic> deepCopyJson(Map<String, dynamic> src) {
  Object? walk(Object? v) => switch (v) {
        final Map m => {for (final e in m.entries) e.key as String: walk(e.value)},
        final List l => [for (final e in l) walk(e)],
        _ => v,
      };
  return walk(src) as Map<String, dynamic>;
}

/// Anything that can be part of a superset — a routine entry or a running workout entry.
///
/// Both carry `sg`, and `supersetUnits` groups either kind, so the shared shape is spelled out
/// rather than left to duck typing.
abstract interface class HasSuperset {
  String? get sg;
}
