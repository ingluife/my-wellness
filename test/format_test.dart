import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_wellness/domain/format.dart';

void main() {
  setUpAll(() async => initializeDateFormatting());

  test('weekKey matches the JavaScript implementation over three years', () {
    // The fixture is the output of openGym's own weekKey, evaluated from its source — see
    // tool/gen_weekkey_fixture.mjs. Year boundaries are the whole point: 2024-12-30 belongs
    // to week 2025-1, and 2026 runs to week 53.
    final expected = jsonDecode(File('test/fixtures/week_keys.json').readAsStringSync())
        as Map<String, dynamic>;
    final mismatches = <String>[];
    expected.forEach((iso, want) {
      final got = weekKey(iso);
      if (got != want) mismatches.add('$iso: want $want, got $got');
    });
    expect(mismatches, isEmpty, reason: mismatches.take(10).join('\n'));
    expect(expected.length, 1110);
  });

  test('jsDay follows getDay(), with Sunday at 0', () {
    expect(jsDay(DateTime(2026, 8, 23)), 0); // Sunday
    expect(jsDay(DateTime(2026, 8, 24)), 1); // Monday
    expect(jsDay(DateTime(2026, 8, 29)), 6); // Saturday
  });

  test('dayOf parses at noon so a DST shift cannot move the day', () {
    final d = dayOf('2026-03-29');
    expect(d.hour, 12);
    expect(isoOf(d), '2026-03-29');
  });

  test('fmtDur reads as minutes below an hour and h/m above it', () {
    expect(fmtDur(0), '0 min');
    expect(fmtDur(59 * 60000), '59 min');
    expect(fmtDur(60 * 60000), '1h 0m');
    expect(fmtDur(95 * 60000), '1h 35m');
  });

  test('durPart drops a duration an import could not know', () {
    expect(durPart(0), isEmpty);
    expect(durPart(59999), isEmpty);
    expect(durPart(90 * 60000), ['1h 30m']);
  });

  test('fmtNum rounds to one decimal and follows the UI language', () {
    expect(fmtNum(62.54), '62.5');
    expect(fmtNum(62.55), '62.6');
    expect(fmtNum(8), '8');
    expect(fmtVol(7535.49, 'kg'), '7,535.5 kg');
  });

  test('uid is base36 and does not collide across a tight loop', () {
    final ids = {for (var i = 0; i < 5000; i++) uid()};
    expect(ids.length, 5000);
    expect(ids.every((s) => RegExp(r'^[0-9a-z]+$').hasMatch(s)), isTrue);
  });

  test('mondayOf lands on the Monday of that ISO week', () {
    expect(isoOf(DateTime.fromMillisecondsSinceEpoch(mondayOf('2026-08-23'))), '2026-08-17');
    expect(isoOf(DateTime.fromMillisecondsSinceEpoch(mondayOf('2026-08-24'))), '2026-08-24');
  });
}
