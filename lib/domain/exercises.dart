import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../data/models/app_state.dart';
import 'i18n.dart';

/// One exercise, from the bundled dataset or created by the user.
class Exercise {
  const Exercise({
    required this.id,
    required this.n,
    required this.bp,
    required this.eq,
    this.tg = '',
    this.mg = '',
    this.sm = const [],
    this.st = const [],
    this.img,
    this.gif,
    this.desc = '',
    this.custom = false,
    this.missing = false,
  });

  final String id;

  /// Name. Arrives lowercase from the dataset, which is why the UI capitalises it.
  final String n;

  /// Body part — the ten top-level groups the library filters by.
  final String bp;

  /// Equipment.
  final String eq;

  /// Target muscle, and the muscle group it belongs to.
  final String tg;
  final String mg;

  /// Secondary muscles, and the English how-to steps.
  final List<String> sm;
  final List<String> st;

  /// Media filenames, relative to assets/img and assets/gif. Custom exercises have neither.
  final String? img;
  final String? gif;

  /// Free text, custom exercises only.
  final String desc;
  final bool custom;

  /// A placeholder for an id nothing resolves — see [Exercises.or].
  final bool missing;

  factory Exercise.fromJson(Map<String, dynamic> j) => Exercise(
        id: j['id'] as String,
        n: j['n'] as String? ?? '',
        bp: j['bp'] as String? ?? '',
        eq: j['eq'] as String? ?? '',
        tg: j['tg'] as String? ?? '',
        mg: j['mg'] as String? ?? '',
        sm: [for (final s in (j['sm'] as List? ?? const [])) s as String],
        st: [for (final s in (j['st'] as List? ?? const [])) s as String],
        img: j['img'] as String?,
        gif: j['gif'] as String?,
        desc: j['desc'] as String? ?? '',
      );

  factory Exercise.fromCustom(CustomExercise c) => Exercise(
        id: c.id,
        n: c.n,
        bp: c.bp,
        eq: c.eq,
        tg: c.tg,
        desc: c.desc,
        custom: true,
      );

  /// Instructions in the current UI language, English as the fallback.
  List<String> get steps => I18n.instance.instrFor(id, st);
}

/// The exercise catalogue: the 1,324 bundled exercises plus whatever the profile has added.
///
/// A singleton with a global id index, matching `EXIDX` in lib/exercises.js — the whole app
/// looks an exercise up by the id stored on a routine entry or a logged set, and that lookup
/// has to keep working for custom exercises too.
class Exercises {
  Exercises._();

  static final Exercises instance = Exercises._();

  final List<Exercise> _db = [];
  final Map<String, Exercise> _index = {};
  List<String> _bodyParts = const [];
  List<String> _customIds = const [];

  /// The bundled dataset, without the profile's own exercises.
  List<Exercise> get db => List.unmodifiable(_db);

  /// Body parts present in the dataset, sorted — the library's filter chips.
  List<String> get bodyParts => _bodyParts;

  bool get isLoaded => _db.isNotEmpty;

  Future<void> load() async {
    if (isLoaded) return;
    final raw = jsonDecode(await rootBundle.loadString('assets/data/exercises.json')) as List;
    for (final e in raw) {
      final ex = Exercise.fromJson(Map<String, dynamic>.from(e as Map));
      _db.add(ex);
      _index[ex.id] = ex;
    }
    _bodyParts = (_db.map((e) => e.bp).toSet().toList()..sort());
  }

  /// Merges the profile's custom exercises into the id index, so every lookup keeps working
  /// unchanged. Called on every persist, as the source does.
  void registerCustom(List<CustomExercise> list) {
    for (final id in _customIds) {
      _index.remove(id);
    }
    _customIds = [for (final c in list) c.id];
    for (final c in list) {
      _index[c.id] = Exercise.fromCustom(c);
    }
  }

  Exercise? operator [](String? id) => id == null ? null : _index[id];

  /// An id that resolves to nothing — a plan file built against a different dataset, or a
  /// custom exercise deleted on another device before the sync arrived — still has to render.
  /// A placeholder keeps it visible (and removable) rather than taking the whole view down on
  /// the first `ex.n`.
  Exercise or(String id) =>
      _index[id] ?? Exercise(id: id, n: t('Unknown exercise'), bp: '', eq: '', missing: true);

  /// The full searchable catalogue — customs first, so your own exercises are easy to find.
  List<Exercise> all(AppState s) =>
      [for (final c in s.customEx) Exercise.fromCustom(c), ..._db];

  /// Cardio exercises log time + speed instead of weight x reps.
  bool isCardio(String? id) => this[id]?.bp == 'cardio';

  /// Exercises the dataset already knows carry no external load — a quarter of the catalogue.
  /// This only *seeds* the bodyweight flag on a fresh config: the flag lives on the config, so
  /// a dip done with a belt can turn it off and a custom exercise can turn it on.
  bool isBodyweightEq(String? id) => this[id]?.eq == 'body weight';

  /// Equipment options present in a given list, most common first.
  ///
  /// Derived from the *already filtered* list, which keeps the chip row short and means every
  /// body-part x equipment combination on screen has results behind it.
  List<String> equipmentOf(Iterable<Exercise> list) {
    final c = <String, int>{};
    for (final e in list) {
      if (e.eq.isNotEmpty) c[e.eq] = (c[e.eq] ?? 0) + 1;
    }
    return c.keys.toList()
      ..sort((a, b) {
        final d = c[b]! - c[a]!;
        return d != 0 ? d : a.compareTo(b);
      });
  }
}

/// Shorthand, so call sites read like the JavaScript's `EXIDX[id]` / `exOr(id)`.
Exercises get exdb => Exercises.instance;
