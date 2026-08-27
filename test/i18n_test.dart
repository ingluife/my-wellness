import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_open_gym/domain/i18n.dart';

/// Guards the shipped language packs.
///
/// `assets/i18n/*.json` is written by tool/gen_i18n.mjs — the UI strings from openGym's own
/// locales, merged with the nutrition strings in tool/locales_nutrition/, which have no upstream.
/// Nobody reviews 1,190 entries x 11 languages by hand, so these are the checks that catch the
/// mistakes that survive review: a language that silently lost keys in a regeneration, a
/// translation that dropped a `{0}` and would render a sentence with a hole in it, and a stray
/// character from the wrong alphabet.
void main() {
  final packs = {
    for (final l in langs.keys.where((l) => l != 'en'))
      l: Map<String, String>.from(
          jsonDecode(File('assets/i18n/$l.json').readAsStringSync()) as Map),
  };

  test('every language ships, and none is empty', () {
    expect(packs.keys, hasLength(11));
    for (final e in packs.entries) {
      expect(e.value, isNotEmpty, reason: e.key);
    }
  });

  test('all languages carry exactly the same keys', () {
    final reference = packs['es']!.keys.toSet();
    for (final e in packs.entries) {
      expect(e.value.keys.toSet().difference(reference), isEmpty,
          reason: '${e.key} has keys no other language has');
      expect(reference.difference(e.value.keys.toSet()), isEmpty,
          reason: '${e.key} is missing keys the others have');
    }
  });

  test('the nutrition strings are present in every language', () {
    final groups = jsonDecode(File('tool/nutrition_keys.json').readAsStringSync()) as Map;
    final expected = [for (final g in groups.values) ...(g as List).cast<String>()];
    expect(expected, hasLength(740));
    for (final e in packs.entries) {
      final missing = expected.where((k) => !e.value.containsKey(k)).toList();
      expect(missing, isEmpty, reason: '${e.key} is missing ${missing.length} nutrition strings');
    }
  });

  test('every translation keeps the placeholders its English key has', () {
    final ph = RegExp(r'\{\d\}');
    List<String> slots(String s) => [for (final m in ph.allMatches(s)) m[0]!]..sort();
    for (final e in packs.entries) {
      for (final kv in e.value.entries) {
        expect(slots(kv.value), equals(slots(kv.key)),
            reason: '${e.key}: "${kv.key}" -> "${kv.value}"');
      }
    }
  });

  test('no translation strays into another alphabet', () {
    const cyrillic = r'Ѐ-ӿ';
    const devanagari = r'ऀ-ॿ';
    const bengali = r'ঀ-৿';
    const han = r'一-鿿';
    const hangul = r'가-힯';
    const latin = '$cyrillic$devanagari$han$hangul';
    final stray = {
      for (final l in ['de', 'es', 'fr', 'it', 'pt', 'pl', 'tr']) l: latin,
      'ru': '$devanagari$han$hangul',
      'zh': '$cyrillic$devanagari$hangul',
      'ko': '$cyrillic$devanagari',
      'hi': '$bengali$cyrillic$han$hangul',
    };
    for (final e in packs.entries) {
      final re = RegExp('[${stray[e.key]!}]');
      for (final kv in e.value.entries) {
        expect(re.hasMatch(kv.value), isFalse,
            reason: '${e.key}: "${kv.key}" -> "${kv.value}"');
      }
    }
  });

  test('every t() literal in the app is actually translated somewhere', () {
    // The direction nothing checked before, and the gap is silent by construction: a `t()` whose
    // key is in no pack falls back to English and renders perfectly, so a screen can ship
    // English-only in all twelve languages without one test going red. That is exactly what
    // happened when the AI screens were added — 53 strings, no failure.
    //
    // German stands in for "some pack has it": every pack carries identical keys, which the test
    // above already asserts.
    final pack = packs['de']!;
    final literal = RegExp(r"\bt\(\s*'((?:[^'\\]|\\.)*)'");

    final missing = <String, Set<String>>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      for (final m in literal.allMatches(f.readAsStringSync())) {
        final key = m[1]!.replaceAll(r"\'", "'");
        if (!pack.containsKey(key)) (missing[f.path] ??= {}).add(key);
      }
    }

    expect(missing, isEmpty,
        reason: 'these strings render English in every language — add them to '
            'tool/nutrition_keys.json and tool/locales_nutrition/*.js, then run '
            'tool/check_i18n_nutrition.mjs and tool/gen_i18n.mjs');
  });

  test('no translation is left blank', () {
    for (final e in packs.entries) {
      for (final kv in e.value.entries) {
        expect(kv.value.trim(), isNotEmpty, reason: '${e.key}: "${kv.key}"');
      }
    }
  });
}
