import 'dart:convert';

import '../data/models/app_state.dart';
import 'exercises.dart';
import 'format.dart';
import 'history.dart';
import 'i18n.dart';

/// Share a weekly plan. Ported from lib/plan-share.js.
///
/// A small, self-contained file a friend can import into their own copy — just the routines,
/// the week schedule, and the custom exercises those routines use. It never carries workouts,
/// weigh-ins or settings, and importing MERGES (adding routines with fresh ids) so nothing the
/// friend already has is touched.

const _planFormat = 1;

/// Mon-first, matching the Plan screen.
const _weekOrder = [1, 2, 3, 4, 5, 6, 0];

/// Keep only the meaningful config fields, so the file stays small and readable.
Map<String, dynamic> _cleanEx(ExerciseConfig e) {
  final o = <String, dynamic>{'id': e.id, 'sets': jsonNum(e.sets ?? 1)};
  final mode = modeOf(e);
  if (mode == 'cardio') {
    putNum(o, 'min', e.min);
    putNum(o, 'speed', e.speed);
  } else if (mode == 'time') {
    // Written out even though 'reps' is the fallback for a non-cardio id: a plan file that
    // dropped the mode would turn a 45-second plank into a 45-rep one at the other end.
    o['mode'] = 'time';
    putNum(o, 'sec', e.sec);
    if ((e.weight ?? 0) != 0) putNum(o, 'weight', e.weight);
  } else {
    putNum(o, 'reps', e.reps);
    if ((e.weight ?? 0) != 0) putNum(o, 'weight', e.weight);
  }
  // How the exercise is logged travels too — the bodyweight flag only when it disagrees with
  // the catalogue, since agreeing is what the other end already assumes.
  if (e.bodyweight != null && e.bodyweight != exdb.isBodyweightEq(e.id)) {
    o['bodyweight'] = e.bodyweight;
  }
  // Only on reps work — `side` counts reps, and a timed hold has none to split.
  if ((e.side ?? false) && mode != 'time' && mode != 'cardio') o['side'] = true;
  // Progression settings travel with the plan — a shared Greyskull routine that arrives
  // without its rule is just a list of weights.
  put(o, 'prog', e.prog);
  if ((e.inc ?? 0) > 0) putNum(o, 'inc', e.inc);
  putNum(o, 'repsMin', e.repsMin);
  putNum(o, 'repsMax', e.repsMax);
  put(o, 'sg', e.sg);
  return o;
}

/// Build the shareable bundle: every routine, the week schedule, referenced customs.
Map<String, dynamic> buildPlanBundle(AppState s, String name) {
  final routines = [
    for (final r in s.routines)
      {
        'id': r.id,
        'name': r.name,
        if (r.emoji != null) 'emoji': r.emoji,
        if (r.prog != null) 'prog': r.prog,
        'ex': [for (final e in r.ex) _cleanEx(e)],
      }
  ];
  final usedIds = {
    for (final r in routines)
      for (final e in r['ex'] as List) (e as Map)['id'] as String?
  };
  final customEx = [
    for (final c in s.customEx)
      if (usedIds.contains(c.id))
        {
          'id': c.id,
          'n': c.n,
          'bp': c.bp,
          if (c.desc.isNotEmpty) 'desc': c.desc,
        }
  ];
  final week = <String, String>{};
  for (final d in _weekOrder) {
    final v = s.week['$d'];
    if (v != null) week['$d'] = v;
  }
  return {
    'opengym_plan': _planFormat,
    'exported': todayISO(),
    'name': name,
    'week': week,
    'routines': routines,
    'customEx': customEx,
  };
}

/// A plan file, validated and counted.
class PlanBundle {
  const PlanBundle({
    required this.name,
    required this.routines,
    required this.week,
    required this.customEx,
    required this.dropped,
  });

  final String name;
  final List<Map<String, dynamic>> routines;
  final Map<String, String> week;
  final List<Map<String, dynamic>> customEx;

  /// Exercises the file named that nothing here can resolve.
  final int dropped;

  int get routineCount => routines.length;

  int get exerciseCount =>
      routines.fold(0, (n, r) => n + (r['ex'] as List).length);

  int get scheduledDays => _weekOrder.where((d) => week.containsKey('$d')).length;
}

/// Validate and normalise an imported file. Throws with a friendly message if it is not one.
///
/// Every exercise id has to resolve — either to the built-in library, or to a custom exercise
/// carried in the same file. An id that resolves to neither (a hand-edited file, an export
/// from a build with a different exercise dataset) is dropped here: kept, it would sit
/// invisibly in the routine and only surface as a blank screen when the routine is trained.
PlanBundle parsePlan(String raw) {
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    throw FormatException(t('this isn’t an openGym plan file'));
  }
  if (decoded is! Map ||
      decoded['opengym_plan'] == null ||
      decoded['routines'] is! List) {
    throw FormatException(t('this isn’t an openGym plan file'));
  }
  final data = Map<String, dynamic>.from(decoded);

  final customEx = [
    for (final c in (data['customEx'] is List ? data['customEx'] as List : const []))
      if (c is Map && c['id'] != null) Map<String, dynamic>.from(c)
  ];
  final known = {for (final c in customEx) c['id'] as String};

  var dropped = 0;
  final routines = <Map<String, dynamic>>[];
  for (final r in data['routines'] as List) {
    if (r is! Map || r['ex'] is! List) continue;
    final kept = <Map<String, dynamic>>[];
    for (final e in r['ex'] as List) {
      final id = e is Map ? e['id'] as String? : null;
      if (id != null && (known.contains(id) || exdb[id] != null)) {
        kept.add(Map<String, dynamic>.from(e as Map));
      } else {
        dropped++;
      }
    }
    routines.add({...Map<String, dynamic>.from(r), 'ex': kept});
  }

  return PlanBundle(
    name: (data['name'] as String? ?? '').trim(),
    routines: routines,
    week: {
      for (final e in (data['week'] is Map ? data['week'] as Map : const {}).entries)
        if (e.value is String) '${e.key}': e.value as String
    },
    customEx: customEx,
    dropped: dropped,
  );
}

/// Merge a parsed bundle into a draft state.
///
///  - customs: reuse one you already have with the same name and body part, else add it fresh
///  - routines: always added as NEW routines with fresh ids — never overwrites yours
///  - schedule: optional; when on, the shared week REPLACES yours, because a half-overwritten
///    week would silently mix two plans
void mergePlan(AppState s, PlanBundle bundle, {bool schedule = false}) {
  final exIdMap = <String, String>{};
  for (final c in bundle.customEx) {
    final n = (c['n'] as String? ?? '').toLowerCase();
    final bp = c['bp'] as String? ?? '';
    final same = s.customEx.where((x) => x.n.toLowerCase() == n && x.bp == bp).firstOrNull;
    if (same != null) {
      exIdMap[c['id'] as String] = same.id;
      continue;
    }
    final nid = uid();
    exIdMap[c['id'] as String] = nid;
    s.customEx.add(CustomExercise(
      id: nid,
      n: c['n'] as String? ?? '',
      bp: bp,
      desc: c['desc'] as String? ?? '',
    ));
  }

  final ridMap = <String, String>{};
  for (final r in bundle.routines) {
    final nid = uid();
    ridMap[r['id'] as String? ?? nid] = nid;
    s.routines.add(Routine(
      id: nid,
      name: (r['name'] as String?)?.isNotEmpty == true
          ? r['name'] as String
          : t('Shared routine'),
      emoji: r['emoji'] as String?,
      prog: r['prog'] as String?,
      ex: [
        for (final e in r['ex'] as List)
          ExerciseConfig.fromJson(Map<String, dynamic>.from(e as Map))
            ..id = exIdMap[e['id']] ?? e['id'] as String?
      ],
    ));
  }

  if (schedule) {
    for (final d in _weekOrder) {
      s.week.remove('$d');
    }
    bundle.week.forEach((d, oldId) {
      final mapped = ridMap[oldId];
      if (mapped != null) s.week[d] = mapped;
    });
  }
}
