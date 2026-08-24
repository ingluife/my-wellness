import 'dart:math' as math;

import '../data/models/app_state.dart';
import 'exercises.dart';
import 'format.dart';

/// Import a training history exported from another app. Ported from lib/import-csv.js.
///
/// Every one of these apps exports the same thing in a different dialect: one row per *set*,
/// carrying a date, an exercise name and some mix of weight/reps/distance/time. So this reads
/// a column map built from the header rather than fixed positions, which means a new app is
/// usually a few header aliases rather than another importer.
///
/// Verified against real exports:
///   FitNotes (Android) Date,Exercise,Category,Weight,Weight Unit,Reps,Distance,...
///   FitNotes 2 (iOS)   Date,Exercise,Category,Weight (kg),Weight (lbs),Reps,...,Kind
///   Strong             Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,...,RPE
///   Hevy               title,start_time,...,exercise_title,...,set_index,set_type,weight_kg,...
/// Anything else falls through to loose header matching, which covers the spreadsheet
/// round-trips people actually have on disk, as long as the file has a date, an exercise name
/// and something measured.
///
/// Apple Health is a different animal — an XML dump, often hundreds of MB — and only its
/// body-weight records are interesting here.

/* ------------------------------------------------------------------- CSV -- */

/// A real CSV reader: quoted fields, embedded commas and newlines, doubled quotes, BOM and
/// CRLF.
///
/// Splitting on commas breaks on the first exercise named "Bench Press, Close Grip" — and a
/// whole history would import shifted by one column without ever erroring.
List<List<String>> parseCSV(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  final s = text.startsWith('﻿') ? text.substring(1) : text;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.any((x) => x.isNotEmpty)) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < s.length && s[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      quoted = true;
    } else if (c == ',') {
      endField();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < s.length && s[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(c);
    }
  }
  endRow();
  return rows;
}

String _norm(String h) =>
    h.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Header text -> the field we care about. Specific names first; first match wins.
const _columns = <(String, List<String>)>[
  ('exercise', ['exercise', 'exercise name', 'exercise title']),
  ('date', ['date', 'workout date']),
  ('startTime', ['start time']),
  ('endTime', ['end time']),
  ('workoutName', ['workout name', 'title']),
  ('category', ['category', 'body part', 'muscle group']),
  ('weightKg', ['weight kg']),
  ('weightLb', ['weight lbs', 'weight lb']),
  ('weight', ['weight']),
  ('weightUnit', ['weight unit', 'unit']),
  ('reps', ['reps', 'repetitions']),
  // Hevy and Strong both write an RPE per set. Nothing mainstream exports RIR, but read it
  // when it is there rather than dropping the column on the floor.
  ('rpe', ['rpe', 'rpe rating']),
  ('rir', ['rir', 'reps in reserve']),
  ('distanceKm', ['distance km']),
  ('distance', ['distance']),
  ('distanceUnit', ['distance unit']),
  ('seconds', ['seconds', 'duration seconds']),
  ('time', ['time', 'duration']),
  ('setType', ['set type']),
  ('note', ['comment', 'comments', 'notes', 'note']),
];

Map<String, int> _mapHeader(List<String> header) {
  final map = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    final n = _norm(header[i]);
    for (final (field, names) in _columns) {
      if (!map.containsKey(field) && names.contains(n)) {
        map[field] = i;
        break;
      }
    }
  }
  return map;
}

/// The app a header looks like — shown back so the numbers can be sanity-checked.
String? detectSource(List<String> header) {
  final h = header.map(_norm).toList();
  if (h.contains('exercise title') && h.contains('set index')) return 'Hevy';
  if (h.contains('exercise name') && h.contains('set order')) return 'Strong';
  if (h.contains('exercise') && h.contains('kind')) return 'FitNotes (iOS)';
  if (h.contains('exercise') && h.contains('weight unit')) return 'FitNotes';
  if (h.contains('exercise') && h.contains('category')) return 'FitNotes';
  return null;
}

/* -------------------------------------------------------- name matching -- */

/// Other apps bolt qualifiers onto names — Hevy writes "Leg Press (Machine)", Strong
/// "Snatch (Barbell)" — while the dataset writes "barbell snatch". Strip the parentheses,
/// expand the shorthand, then compare as a sorted bag of words so word order stops mattering.
final _synonyms = <(RegExp, String)>[
  (RegExp(r'\bbb\b'), 'barbell'),
  (RegExp(r'\bdb\b'), 'dumbbell'),
  (RegExp(r'\bkb\b'), 'kettlebell'),
  (RegExp(r'\bohp\b'), 'overhead press'),
  (RegExp(r'\bbw\b'), 'body weight'),
  (RegExp(r'\bbodyweight\b'), 'body weight'),
  (RegExp(r'\bmachine\b'), 'lever'),
  (RegExp(r'\bsmith machine\b'), 'smith'),
  (RegExp(r'\bez bar\b'), 'ez barbell'),
  (RegExp(r'\bpull ups?\b'), 'pull up'),
  (RegExp(r'\bchin ups?\b'), 'chin up'),
  (RegExp(r'\bpush ups?\b'), 'push up'),
  (RegExp(r'\bsit ups?\b'), 'sit up'),
  (RegExp(r'\bdips?\b'), 'dip'),
  (RegExp(r'\braises?\b'), 'raise'),
  (RegExp(r'\bcurls?\b'), 'curl'),
  (RegExp(r'\bpresses\b'), 'press'),
  (RegExp(r'\bextensions?\b'), 'extension'),
  (RegExp(r'\bcables?\b'), 'cable'),
];

/// Words that say nothing about which exercise this is, so they should not stop a match.
const _filler = {'the', 'a', 'with', 'and', 'v', 'variation', 'version', 'pulley', 'weighted'};

List<String> _wordsOf(String? name) {
  // Parentheses are unwrapped rather than dropped: "Bench Press (Barbell)" carries its
  // equipment in there, and the dataset writes that as "barbell bench press".
  var k = (name ?? '')
      .toLowerCase()
      .replaceAll(RegExp(r'[()\[\]]'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
  for (final (re, to) in _synonyms) {
    k = k.replaceAll(re, to);
  }
  return k.split(' ').where((w) => w.isNotEmpty && !_filler.contains(w)).toList();
}

String _keyOf(String? name) => (_wordsOf(name)..sort()).join(' ');

class _NameIndex {
  _NameIndex(this.exact, this.all);

  final Map<String, String> exact;
  final List<({String id, Set<String> words, int n})> all;
}

_NameIndex? _index;

_NameIndex _buildIndex() {
  if (_index != null) return _index!;
  final exact = <String, String>{};
  final all = <({String id, Set<String> words, int n})>[];
  for (final e in exdb.db) {
    final w = _wordsOf(e.n);
    final k = (List.of(w)..sort()).join(' ');
    exact.putIfAbsent(k, () => e.id);
    all.add((id: e.id, words: w.toSet(), n: w.length));
  }
  return _index = _NameIndex(exact, all);
}

/// Curated: the names people actually log, mapped by hand to the dataset id they mean.
///
/// Other apps let you name a lift "Bench Press"; the dataset only has qualified names like
/// "barbell bench press". Word overlap alone cannot resolve that — "bench press" sits inside
/// thirty-three entries — and where it *is* unique it tends to be wrong, happily resolving
/// "Squat" to "weighted squat" and "Leg Press" to "smith leg press". So the common vocabulary
/// is spelled out. The convention is that an unqualified name means the canonical barbell
/// version, which is what these apps assume when they show it to you. Extending this table is
/// the intended way to improve import accuracy.
const _aliasEx = <String, String>{
  'bench press': '0025', 'barbell bench press': '0025', 'flat bench press': '0025',
  'incline bench press': '0047', 'decline bench press': '0033',
  'close grip bench press': '0030', 'close-grip bench press': '0030',
  'squat': '0043', 'back squat': '0043', 'barbell squat': '0043', 'front squat': '0042',
  'deadlift': '0032', 'romanian deadlift': '0085', 'rdl': '0085', 'sumo deadlift': '0117',
  'lat pulldown': '2330', 'lat pull down': '2330', 'pulldown': '2330',
  'shrug': '0095', 'shrugs': '0095',
  'overhead press': '0091', 'military press': '0091', 'shoulder press': '0091', 'ohp': '0091',
  'barbell row': '0027', 'bent over row': '0027', 'bent-over row': '0027',
  'dumbbell row': '0292', 'one arm dumbbell row': '0292',
  'leg curl': '0586', 'lying leg curl': '0586', 'seated leg curl': '0586',
  'leg press': '0739', 'leg extension': '0585',
  'calf raise': '1372', 'standing calf raise': '1372', 'seated calf raise': '0088',
  'lateral raise': '0334', 'side raise': '0334', 'reverse fly': '0348', 'rear delt fly': '0348',
  'bicep curl': '0294', 'biceps curl': '0294', 'dumbbell curl': '0294',
  'preacher curl': '0070', 'barbell curl': '0031',
  'tricep pushdown': '0241', 'triceps pushdown': '0241', 'pushdown': '0241',
  'skullcrusher': '0060', 'skull crusher': '0060', 'lying triceps extension': '0061',
  'lunge': '0054', 'lunges': '0054', 'cable crossover': '1269', 'cable cross over': '1269',
};

Map<String, String>? _aliasIndex;

Map<String, String> _aliases() =>
    _aliasIndex ??= {for (final e in _aliasEx.entries) _keyOf(e.key): e.value};

/// Find the dataset exercise a foreign name refers to, or null.
///
/// Curated alias first, then an exact word-bag match, then entries that contain every word of
/// the query — but only when exactly one candidate is that close. Guessing between "barbell
/// bench press" and "dumbbell bench press" would file years of training under the wrong lift,
/// which is worse than leaving it as a custom exercise the user can see and fix.
String? matchExercise(String? name) {
  final idx = _buildIndex();
  final w = _wordsOf(name);
  if (w.isEmpty) return null;

  // Compared as a sorted bag of words, so "Squat (Barbell)" finds the 'barbell squat' alias —
  // the exporters disagree about whether the equipment leads or trails.
  final sorted = (List.of(w)..sort()).join(' ');
  final aliased = _aliases()[sorted];
  if (aliased != null && exdb[aliased] != null) return aliased;
  final exact = idx.exact[sorted];
  if (exact != null) return exact;

  final q = w.toSet();
  String? best;
  var bestExtra = 1 << 30;
  var ties = 0;
  for (final c in idx.all) {
    if (!q.every(c.words.contains)) continue;
    final extra = c.n - q.length;
    if (extra > 2) continue;
    if (extra < bestExtra) {
      best = c.id;
      bestExtra = extra;
      ties = 1;
    } else if (extra == bestExtra) {
      ties++;
    }
  }
  return ties == 1 ? best : null;
}

/// Categories the exporters use -> the dataset's body parts, for exercises we invent.
const _categoryBp = <String, String>{
  'chest': 'chest', 'back': 'back', 'lats': 'back', 'shoulders': 'shoulders',
  'delts': 'shoulders', 'legs': 'upper legs', 'quads': 'upper legs',
  'hamstrings': 'upper legs', 'glutes': 'upper legs', 'calves': 'lower legs',
  'abs': 'waist', 'core': 'waist', 'obliques': 'waist', 'arms': 'upper arms',
  'biceps': 'upper arms', 'triceps': 'upper arms', 'forearms': 'lower arms',
  'cardio': 'cardio', 'full body': 'upper legs', 'olympic': 'upper legs', 'neck': 'neck',
};

/* --------------------------------------------------------- conversion ----- */

double _num(Object? v) {
  final n = double.tryParse((v ?? '').toString().replaceAll(',', '.'));
  return n != null && n.isFinite ? n : 0;
}

/// An effort rating out of someone else's export.
///
/// A blank cell means "not rated" and has to stay absent rather than becoming 0 — and 0 itself
/// means opposite things on the two scales: RIR 0 is a set taken to failure and worth keeping,
/// while RPE has no 0 (the scale is 1–10), so an app writing 0 for "nothing here" must not be
/// read as an effort. Ratings above the scale are capped rather than dropped — the set was
/// still rated, just written oddly.
double? _effortNum(String? raw, bool zeroMeansRated) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return null;
  final n = double.tryParse(s.replaceAll(',', '.'));
  if (n == null || !n.isFinite || n < 0 || (n == 0 && !zeroMeansRated)) return null;
  return math.min(10, (n * 100).round() / 100);
}

const _lbToKg = 0.45359237;

String _p2(int n) => n.toString().padLeft(2, '0');

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

typedef When = ({String d, int? t});

int? _hm(String? h, String? mi) =>
    h == null ? null : (int.tryParse(h) ?? 0) * 3600000 + (int.tryParse(mi ?? '') ?? 0) * 60000;

/// "2020-12-30 18:51:52" · "2024-03-07" · "22 Dec 2025, 08:00" · "07/03/2024"
When? parseWhen(String? s) {
  final v = (s ?? '').trim();

  var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[T ](\d{1,2}):(\d{2}))?').firstMatch(v);
  if (m != null) {
    return (
      d: '${m[1]}-${_p2(int.parse(m[2]!))}-${_p2(int.parse(m[3]!))}',
      t: _hm(m[4], m[5])
    );
  }

  m = RegExp(r'^(\d{1,2})\s+([A-Za-z]{3})[a-z]*\.?\s+(\d{4})(?:,?\s+(\d{1,2}):(\d{2}))?')
      .firstMatch(v);
  if (m != null && _months.containsKey(m[2]!.toLowerCase())) {
    return (
      d: '${m[3]}-${_p2(_months[m[2]!.toLowerCase()]!)}-${_p2(int.parse(m[1]!))}',
      t: _hm(m[4], m[5])
    );
  }

  m = RegExp(r'^([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2}),?\s+(\d{4})(?:,?\s+(\d{1,2}):(\d{2}))?')
      .firstMatch(v);
  if (m != null && _months.containsKey(m[1]!.toLowerCase())) {
    return (
      d: '${m[3]}-${_p2(_months[m[1]!.toLowerCase()]!)}-${_p2(int.parse(m[2]!))}',
      t: _hm(m[4], m[5])
    );
  }

  // Day-first when ambiguous: FitNotes/Strong/Hevy all write unambiguous dates, so a bare
  // numeric one came through a spreadsheet, and those are usually European.
  m = RegExp(r'^(\d{1,2})[/.](\d{1,2})[/.](\d{4})(?:[, ]+(\d{1,2}):(\d{2}))?').firstMatch(v);
  if (m != null) {
    final a = int.parse(m[1]!);
    final b = int.parse(m[2]!);
    final day = a > 12 ? a : (b > 12 ? b : a);
    final mon = day == a ? b : a;
    return (d: '${m[3]}-${_p2(mon)}-${_p2(day)}', t: _hm(m[4], m[5]));
  }
  return null;
}

/// "HH:MM:SS" · "MM:SS" · "90" · Strong's "2h 38m" -> minutes
double _toMinutes(String? v) {
  final s = (v ?? '').trim();
  if (s.isEmpty) return 0;
  if (s.contains(':')) {
    final p = s.split(':').map((x) => int.tryParse(x) ?? 0).toList();
    final sec = p.length == 3 ? p[0] * 3600 + p[1] * 60 + p[2] : p[0] * 60 + p[1];
    return (sec / 60 * 10).round() / 10;
  }
  final h = RegExp(r'(\d+)\s*h', caseSensitive: false).firstMatch(s);
  final mm = RegExp(r'(\d+)\s*m', caseSensitive: false).firstMatch(s);
  if (h != null || mm != null) {
    return ((h != null ? int.parse(h[1]!) * 60 : 0) + (mm != null ? int.parse(mm[1]!) : 0))
        .toDouble();
  }
  return (_num(s) * 10).round() / 10;
}

const _km = <String, double>{
  'm': 0.001, 'km': 1, 'cm': 0.00001, 'in': 0.0000254,
  'ft': 0.0003048, 'yd': 0.0009144, 'mi': 1.609344,
};

double _toKmValue(String? v, String? unit) =>
    _num(v) * (_km[(unit ?? 'km').toLowerCase().trim()] ?? 1);

/* ------------------------------------------------------------- results ---- */

/// What a file would do, before anything is written.
class ImportResult {
  ImportResult({
    this.error,
    this.kind = '',
    this.source,
    List<Workout>? workouts,
    List<CustomExercise>? customEx,
    List<BodyWeightEntry>? bodyweight,
    this.matched = 0,
    this.matchedSets = 0,
    this.created = 0,
    List<String>? unmatchedNames,
    this.sets = 0,
    this.skipped = 0,
    this.warmups = 0,
    this.fileUnit = '',
    this.mixedUnits = false,
    this.converted = false,
    this.rpeSets = 0,
    this.rirSets = 0,
    this.from,
    this.to,
  })  : workouts = workouts ?? [],
        customEx = customEx ?? [],
        bodyweight = bodyweight ?? [],
        unmatchedNames = unmatchedNames ?? [];

  /// 'empty' | 'unrecognised', or null when the file parsed.
  final String? error;

  /// 'workouts' | 'bodyweight'
  final String kind;
  final String? source;

  final List<Workout> workouts;
  final List<CustomExercise> customEx;
  final List<BodyWeightEntry> bodyweight;

  /// Distinct library exercises behind the matched rows — the summary calls this "exercises
  /// matched", and counting rows there made three exercises read as five.
  final int matched;
  final int matchedSets;
  final int created;
  final List<String> unmatchedNames;
  final int sets;
  final int skipped;
  final int warmups;
  final String fileUnit;
  final bool mixedUnits;
  final bool converted;
  final int rpeSets;
  final int rirSets;
  final String? from;
  final String? to;

  bool get isBodyweight => kind == 'bodyweight';
}

/// Read an export into workouts openGym understands, WITHOUT touching state — the caller shows
/// the summary for confirmation first.
///
/// Nothing here throws on a bad row: a history of several thousand sets will contain oddities,
/// and losing the file over one of them helps nobody. Bad rows are counted and reported.
ImportResult parseWorkoutCSV(String text, {String unit = 'kg'}) {
  final rows = parseCSV(text);
  if (rows.length < 2) return ImportResult(error: 'empty');
  final map = _mapHeader(rows.first);
  final source = detectSource(rows.first);
  final dateCol = map.containsKey('date')
      ? 'date'
      : (map.containsKey('startTime') ? 'startTime' : null);
  if (dateCol == null || !map.containsKey('exercise')) {
    return ImportResult(error: 'unrecognised');
  }

  // Exercise name -> dataset id or null, resolved once per distinct name.
  final resolved = <String, String?>{};
  final byDate = <String, ({Map<String, List<SetLog>> ex, List<String> name, int? start, int? end})>{};
  final created = <String, CustomExercise>{};
  final rowUnits = <SetLog, String>{};
  final unmatched = <String>{};
  var sets = 0, skipped = 0, matchedSets = 0, warmups = 0, rpeSets = 0, rirSets = 0;
  var sawLb = false, sawKg = false;

  String cell(List<String> r, String f) {
    final i = map[f];
    if (i == null || i >= r.length) return '';
    return r[i].trim();
  }

  for (var i = 1; i < rows.length; i++) {
    final r = rows[i];
    final name = cell(r, 'exercise');
    final when = parseWhen(cell(r, dateCol));
    if (name.isEmpty || when == null) {
      skipped++;
      continue;
    }

    // Explicit kg/lb columns beat a generic column plus a unit column.
    var w = 0.0;
    var rowUnit = '';
    if (map.containsKey('weightKg') && cell(r, 'weightKg').isNotEmpty) {
      w = _num(cell(r, 'weightKg'));
      rowUnit = 'kg';
    } else if (map.containsKey('weightLb') && cell(r, 'weightLb').isNotEmpty) {
      w = _num(cell(r, 'weightLb'));
      rowUnit = 'lb';
    } else {
      w = _num(cell(r, 'weight'));
      final u = cell(r, 'weightUnit').toLowerCase();
      rowUnit = u.startsWith('lb') ? 'lb' : (u.startsWith('kg') ? 'kg' : '');
    }
    if (rowUnit == 'lb') sawLb = true;
    if (rowUnit == 'kg') sawKg = true;

    final reps = _num(cell(r, 'reps')).round();
    final secs = _num(cell(r, 'seconds'));
    final mins = secs > 0 ? (secs / 60 * 10).round() / 10 : _toMinutes(cell(r, 'time'));
    final km = map.containsKey('distanceKm') && cell(r, 'distanceKm').isNotEmpty
        ? _num(cell(r, 'distanceKm'))
        : _toKmValue(cell(r, 'distance'), cell(r, 'distanceUnit'));

    if (w == 0 && reps == 0 && mins == 0 && km == 0) {
      skipped++;
      continue;
    }
    if (RegExp('warm', caseSensitive: false).hasMatch(cell(r, 'setType'))) warmups++;

    final key = _keyOf(name);
    String? id;
    if (resolved.containsKey(key)) {
      id = resolved[key];
    } else {
      id = matchExercise(name);
      resolved[key] = id;
    }
    if (id != null) {
      matchedSets++;
    } else {
      var c = created[key];
      if (c == null) {
        c = CustomExercise(
          id: 'im${uid()}',
          n: name.toLowerCase(),
          bp: _categoryBp[cell(r, 'category').toLowerCase()] ??
              ((km > 0 || (mins > 0 && reps == 0)) ? 'cardio' : 'upper legs'),
        );
        created[key] = c;
        unmatched.add(name);
      }
      id = c.id;
    }

    final isCardio = (km > 0 || mins > 0) && reps == 0;
    final SetLog set;
    if (isCardio) {
      set = SetLog(
        min: mins,
        speed: mins > 0 ? (km / (mins / 60) * 10).round() / 10 : 0,
        done: true,
      );
    } else {
      set = SetLog(w: w, r: reps.toDouble(), done: true);
      rowUnits[set] = rowUnit;
      // Effort rides along only where the app can show it again: a weighted rep set. A
      // treadmill row with an RPE would have nowhere to put it. A set is kept on one scale, so
      // a file carrying both columns is read as RIR — the precedence setLabel reads them with.
      final rir = _effortNum(cell(r, 'rir'), true);
      final rpe = rir == null ? _effortNum(cell(r, 'rpe'), false) : null;
      if (rir != null) {
        set.rir = rir;
        rirSets++;
      } else if (rpe != null) {
        set.rpe = rpe;
        rpeSets++;
      }
    }

    var day = byDate[when.d];
    if (day == null) {
      day = (ex: <String, List<SetLog>>{}, name: <String>[cell(r, 'workoutName')], start: when.t, end: null);
      byDate[when.d] = day;
    }
    if (day.name.first.isEmpty && cell(r, 'workoutName').isNotEmpty) {
      day.name[0] = cell(r, 'workoutName');
    }
    if (map.containsKey('endTime')) {
      final e = parseWhen(cell(r, 'endTime'));
      if (e != null && e.t != null) {
        byDate[when.d] = (ex: day.ex, name: day.name, start: day.start, end: e.t);
      }
    }
    (byDate[when.d]!.ex[id] ??= <SetLog>[]).add(set);
    sets++;
  }

  // lb -> kg only where a row disagrees with the profile. The app never converts units on its
  // own, so importing unconverted would silently rewrite someone's numbers. Converting PER ROW
  // matters: apps like FitNotes write the unit next to every set, and a history recorded partly
  // in lb and partly in kg used to be taken over as-is, turning "185 lb" into 185 kg.
  final fileUnit = sawLb && !sawKg ? 'lb' : (sawKg && !sawLb ? 'kg' : '');
  final mixedUnits = sawLb && sawKg;
  double toKgV(double x) => (x * _lbToKg * 10).round() / 10;
  double toLbV(double x) => (x / _lbToKg * 10).round() / 10;

  // A row without its own unit follows the file's, and a file that says nothing is taken to
  // already be in the profile's unit.
  double convRow(SetLog s) {
    final u = (rowUnits[s] ?? '').isNotEmpty ? rowUnits[s]! : fileUnit;
    if (u.isEmpty || u == unit) return s.w ?? 0;
    return u == 'lb' ? toKgV(s.w ?? 0) : toLbV(s.w ?? 0);
  }

  final converted = (fileUnit.isNotEmpty && fileUnit != unit) || mixedUnits;
  final dates = byDate.keys.toList()..sort();

  final workouts = <Workout>[];
  for (final d in dates) {
    final day = byDate[d]!;
    final entries = <WorkoutEntry>[];
    day.ex.forEach((id, ss) {
      for (final s in ss) {
        if (s.w != null) s.w = convRow(s);
      }
      final mx = ss.fold(0.0, (m, s) => m > (s.w ?? 0) ? m : (s.w ?? 0));
      entries.add(WorkoutEntry(id: id, sets: ss, topW: mx > 0 ? mx : null, writesTopW: true));
    });
    final base = dayOf(d).millisecondsSinceEpoch - 12 * 3600000;
    final start = base + (day.start ?? 18 * 3600000);
    final end = day.end != null ? base + day.end! : start;
    final w = Workout(
      id: 'iw${uid()}',
      d: d,
      start: start,
      end: end > start ? end : start,
      name: day.name.first.isNotEmpty ? day.name.first : 'Imported',
      entries: entries,
    );
    w.vol = workoutVolumeOf(w);
    workouts.add(w);
  }

  return ImportResult(
    kind: 'workouts',
    source: source,
    workouts: workouts,
    customEx: created.values.toList(),
    matched: resolved.values.whereType<String>().toSet().length,
    matchedSets: matchedSets,
    created: created.length,
    unmatchedNames: unmatched.toList()..sort(),
    sets: sets,
    skipped: skipped,
    warmups: warmups,
    fileUnit: fileUnit,
    mixedUnits: mixedUnits,
    converted: converted,
    rpeSets: rpeSets,
    rirSets: rirSets,
    from: dates.firstOrNull,
    to: dates.lastOrNull,
  );
}

/// Volume of a freshly parsed workout, without importing history.dart into this module.
double workoutVolumeOf(Workout w) {
  var v = 0.0;
  for (final e in w.entries) {
    for (final s in e.sets) {
      if (s.done) v += (s.w ?? 0) * (s.r ?? 0);
    }
  }
  return v;
}

/// Body-weight history from Apple Health, or any CSV with a date and a weight.
///
/// Health's own export is one big `export.xml` — often several hundred MB, nearly all of it
/// step counts and heart rate. Building a DOM would blow up the app, so the body-mass records
/// are pulled out with a scan instead. Health writes weights in the unit the phone is set to
/// and labels each record, so the unit is read per record.
ImportResult parseBodyweight(String text, {String unit = 'kg'}) {
  final out = <String, ({double w, int? t})>{};
  var fileUnit = '';

  if (text.contains('HKQuantityTypeIdentifierBodyMass')) {
    final re = RegExp(r'<Record[^>]*type="HKQuantityTypeIdentifierBodyMass"[^>]*>');
    for (final m in re.allMatches(text)) {
      final tag = m[0]!;
      final val = RegExp(r'value="([\d.]+)"').firstMatch(tag);
      final dt = RegExp(r'startDate="([^"]+)"').firstMatch(tag) ??
          RegExp(r'creationDate="([^"]+)"').firstMatch(tag);
      final u = RegExp(r'unit="([^"]+)"').firstMatch(tag);
      if (val == null || dt == null) continue;
      final when = parseWhen(dt[1]);
      if (when == null) continue;
      if (u != null) {
        fileUnit = RegExp('lb', caseSensitive: false).hasMatch(u[1]!) ? 'lb' : 'kg';
      }
      out[when.d] = (
        w: double.tryParse(val[1]!) ?? 0,
        t: DateTime.tryParse(dt[1]!)?.millisecondsSinceEpoch
      );
    }
  } else {
    final rows = parseCSV(text);
    if (rows.length < 2) return ImportResult(error: 'empty');
    final map = _mapHeader(rows.first);
    // A weight-only CSV: whichever weight column it has.
    final wCol = map['weightKg'] ?? map['weightLb'] ?? map['weight'];
    final dCol = map['date'] ?? map['startTime'];
    if (wCol == null || dCol == null) return ImportResult(error: 'unrecognised');
    if (map.containsKey('weightKg')) {
      fileUnit = 'kg';
    } else if (map.containsKey('weightLb')) {
      fileUnit = 'lb';
    }
    for (var i = 1; i < rows.length; i++) {
      if (dCol >= rows[i].length || wCol >= rows[i].length) continue;
      final when = parseWhen(rows[i][dCol]);
      final w = _num(rows[i][wCol]);
      if (when == null || w == 0) continue;
      out[when.d] =
          (w: w, t: dayOf(when.d).millisecondsSinceEpoch - 12 * 3600000 + (when.t ?? 0));
    }
  }

  if (out.isEmpty) return ImportResult(error: 'unrecognised');
  final converted = fileUnit.isNotEmpty && fileUnit != unit;
  double conv(double x) => converted
      ? (fileUnit == 'lb' ? (x * _lbToKg * 10).round() / 10 : (x / _lbToKg * 10).round() / 10)
      : (x * 10).round() / 10;

  final dates = out.keys.toList()..sort();
  return ImportResult(
    kind: 'bodyweight',
    source: 'Apple Health',
    bodyweight: [
      for (final d in dates)
        BodyWeightEntry(
          d: d,
          w: conv(out[d]!.w),
          t: out[d]!.t ?? (dayOf(d).millisecondsSinceEpoch - 12 * 3600000),
        )
    ],
    fileUnit: fileUnit,
    converted: converted,
    from: dates.first,
    to: dates.last,
  );
}

/// Sniff the file and parse it as whatever it is.
ImportResult parseImport(String text, {String unit = 'kg'}) {
  if (text.contains('HKQuantityTypeIdentifier') || RegExp(r'^\s*<').hasMatch(text)) {
    return parseBodyweight(text, unit: unit);
  }
  final asWorkouts = parseWorkoutCSV(text, unit: unit);
  if (asWorkouts.error == null) return asWorkouts;
  final asWeights = parseBodyweight(text, unit: unit);
  return asWeights.error != null ? asWorkouts : asWeights;
}

/// Merge into state. Existing days win — importing twice never duplicates a workout.
({int added, int skipped}) mergeImport(AppState s, ImportResult parsed) {
  if (parsed.isBodyweight) {
    final have = {for (final b in s.bodyweight) b.d};
    final fresh = parsed.bodyweight.where((b) => !have.contains(b.d)).toList();
    s.bodyweight
      ..addAll(fresh)
      ..sort((a, b) => a.d.compareTo(b.d));
    return (added: fresh.length, skipped: parsed.bodyweight.length - fresh.length);
  }

  final have = {for (final w in s.workouts) w.d};
  final fresh = parsed.workouts.where((w) => !have.contains(w.d)).toList();
  final used = {for (final w in fresh) for (final e in w.entries) e.id};
  s.customEx.addAll(
      parsed.customEx.where((c) => used.contains(c.id) && exdb[c.id] == null));
  s.workouts
    ..addAll(fresh)
    ..sort((a, b) => a.d.compareTo(b.d));

  // Seed the weight suggestions from the newest imported set of each lift.
  for (final w in fresh) {
    for (final e in w.entries) {
      final mx = [
        ...e.sets.map((x) => x.w ?? 0),
        e.topW ?? 0,
      ].fold(0.0, (m, x) => m > x ? m : x);
      if (mx > 0) {
        final cur = s.exWeights[e.id];
        if (cur == null || w.d.compareTo(cur.d) >= 0) {
          s.exWeights[e.id] = ExWeight(w: mx, d: w.d);
        }
      }
    }
  }
  return (added: fresh.length, skipped: parsed.workouts.length - fresh.length);
}
