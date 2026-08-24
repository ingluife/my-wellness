import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_open_gym/data/models/app_state.dart';

/// The single most important test in the project.
///
/// myOpenGym and openGym have to read each other's backups, which means the Dart models must
/// serialise the *same* JSON the JavaScript ones do — same keys, same absences, same number
/// forms. Anything less makes this a lookalike rather than a translation.
void main() {
  final raw = File('test/fixtures/full_state.json').readAsStringSync();
  final source = jsonDecode(raw) as Map<String, dynamic>;

  test('a full-fat state survives fromJson -> toJson unchanged', () {
    final out = AppState.fromJson(source).toJson();
    expect(jsonDecode(jsonEncode(out)), equals(source));
  });

  test('the deep clone update() takes is value-identical to its source', () {
    final s = AppState.fromJson(source);
    final clone = s.copy();
    expect(jsonEncode(clone.toJson()), jsonEncode(s.toJson()));

    // ...and genuinely deep: mutating the clone must not reach into the original, which is
    // what lets a producer function be handed a throwaway draft.
    clone.routines.first.ex.first.weight = 999;
    clone.active!.entries.first.sets.first.done = false;
    expect(s.routines.first.ex.first.weight, 60);
    expect(s.active!.entries.first.sets.first.done, isTrue);
  });

  test('defaults match DEF in useStore.js', () {
    final d = AppState.defaults();
    expect(d.unit, 'kg');
    expect(d.restSec, 90);
    expect(d.sound, isTrue);
    expect(d.keepAwake, isTrue);
    expect(d.lang, 'en');
    expect(d.theme, 'dark');
    expect(d.accent, 'lime');
    expect(d.body, 'male');
    expect(d.gifSize, 'full');
    expect(d.targetW, isNull);
    // null rather than 'none', so a profile that never chose still falls back to showRir.
    expect(d.effort, isNull);
    expect(d.reminder.on, isFalse);
    expect(d.reminder.time, '08:00');
    expect(d.reminder.tz, isNull);
    expect(d.hasData, isFalse);
  });

  test('an unset optional is absent, never null', () {
    final set = SetLog(w: 60, r: 8, done: true).toJson();
    expect(set.keys.toList(), ['w', 'r', 'done']);
    expect(set.containsKey('rir'), isFalse);

    // A cleared effort drops the key rather than storing null — "unrated" and "went to
    // failure" (rir 0) must stay distinguishable.
    final rated = SetLog(w: 60, r: 8, done: true, rir: 0);
    expect(rated.toJson()['rir'], 0);
    rated.setField('rir', null);
    expect(rated.toJson().containsKey('rir'), isFalse);
  });

  test('whole numbers serialise as integers, like JSON.stringify does', () {
    final s = SetLog(w: 62.5, r: 8, done: true).toJson();
    expect(s['r'], isA<int>());
    expect(s['r'], 8);
    expect(s['w'], 62.5);
    expect(jsonEncode(s), '{"w":62.5,"r":8,"done":true}');
  });

  test('keys a newer openGym might add are carried through', () {
    final out = AppState.fromJson(source).toJson();
    expect(out['somethingFromANewerBuild'], source['somethingFromANewerBuild']);
  });
}
