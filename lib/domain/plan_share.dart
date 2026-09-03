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

/// The body of every plan file: the given routines, the customs those routines use, and — for
/// a whole-plan export — the week that schedules them.
Map<String, dynamic> _bundle(AppState s, String name, Iterable<Routine> from,
    {bool withWeek = true}) {
  final routines = [
    for (final r in from)
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
  if (withWeek) {
    for (final d in _weekOrder) {
      final v = s.week['$d'];
      if (v != null) week['$d'] = v;
    }
  }
  return {
    'mywellness_plan': _planFormat,
    'exported': todayISO(),
    'name': name,
    'week': week,
    'routines': routines,
    'customEx': customEx,
  };
}

/// Build the shareable bundle: every routine, the week schedule, referenced customs.
Map<String, dynamic> buildPlanBundle(AppState s, String name) =>
    _bundle(s, name, s.routines);

/// One routine as a plan file of its own — the same envelope, so a friend imports it with the
/// importer they already have.
///
/// The week is deliberately left out: one routine cannot describe somebody's week, and
/// carrying a schedule would offer to replace all seven of their days to deliver one routine.
/// An empty week also keeps the schedule switch out of the import sheet.
Map<String, dynamic> buildRoutineBundle(AppState s, Routine r) =>
    _bundle(s, r.name, [r], withWeek: false);

/// A routine name reduced to something every filesystem and share target accepts.
String _slug(String name) {
  var out = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (out.length > 40) out = out.substring(0, 40).replaceAll(RegExp(r'-+$'), '');
  return out.isEmpty ? 'routine' : out;
}

/// What a shared routine file is called, matching the plan and backup files.
///
/// A name with nothing sluggable in it (`推日`) falls back to `routine`; the real name still
/// travels inside the file and is what the other end's import sheet shows.
String routineFileName(Routine r) =>
    'mywellness-routine-${_slug(r.name)}-${todayISO()}.json';

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
    throw FormatException(t('this isn’t a My Wellness plan file'));
  }
  if (decoded is! Map ||
      decoded['mywellness_plan'] == null ||
      decoded['routines'] is! List) {
    throw FormatException(t('this isn’t a My Wellness plan file'));
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

/// The routine an incoming single-routine file would duplicate, or null.
///
/// Matched on name alone — case-insensitive and trimmed — because that is how someone
/// recognises "I already have this one". A file carrying more than one routine returns null
/// and imports unchanged: asking about five collisions at once would be a worse trade than
/// letting them append. The test is the count, not where the file came from, so a whole-plan
/// export that happens to hold a single routine is offered the same choice — which is what you
/// would want, since such a file is a single-routine share in all but name.
Routine? duplicateOf(AppState s, PlanBundle b) {
  if (b.routines.length != 1) return null;
  final name = ((b.routines.single['name'] as String?) ?? '').trim().toLowerCase();
  if (name.isEmpty) return null;
  return s.routines.where((r) => r.name.trim().toLowerCase() == name).firstOrNull;
}

/// Merge a parsed bundle into a draft state.
///
///  - customs: reuse one you already have with the same name and body part, else add it fresh
///  - routines: always added as NEW routines with fresh ids — never overwrites yours
///  - schedule: optional; when on, the shared week REPLACES yours, because a half-overwritten
///    week would silently mix two plans
///  - replaceId: optional; the one routine to overwrite in place instead of adding. Used when
///    an imported routine collides by name with one you already have and you chose to replace
///    it — see [duplicateOf].
void mergePlan(AppState s, PlanBundle bundle,
    {bool schedule = false, String? replaceId}) {
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
    final ex = [
      for (final e in r['ex'] as List)
        ExerciseConfig.fromJson(Map<String, dynamic>.from(e as Map))
          ..id = exIdMap[e['id']] ?? e['id'] as String?
    ];
    final name = (r['name'] as String?)?.isNotEmpty == true
        ? r['name'] as String
        : t('Shared routine');

    // Replacing keeps the existing id, so whatever weekday the routine is scheduled on stays
    // scheduled — minting a fresh id would silently unschedule it.
    final target = replaceId == null
        ? null
        : s.routines.where((x) => x.id == replaceId).firstOrNull;
    if (target != null) {
      target.name = name;
      target.emoji = r['emoji'] as String?;
      target.prog = r['prog'] as String?;
      target.ex = ex;
      ridMap[r['id'] as String? ?? target.id] = target.id;
      continue;
    }

    final nid = uid();
    ridMap[r['id'] as String? ?? nid] = nid;
    s.routines.add(Routine(
      id: nid,
      name: name,
      emoji: r['emoji'] as String?,
      prog: r['prog'] as String?,
      ex: ex,
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
