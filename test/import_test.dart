import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_open_gym/data/models/app_state.dart';
import 'package:my_open_gym/domain/history.dart';
import 'package:my_open_gym/domain/import_csv.dart';

import 'helpers.dart';

/// Ported from openGym's import-effort.test.js, plus coverage for the parts of the importer
/// its own suite exercises indirectly.
void main() {
  setUpAll(loadExercises);

  // Headers as the real exports write them, trimmed to the columns that matter here.
  const hevy =
      'title,start_time,end_time,exercise_title,set_index,set_type,weight_kg,reps,rpe';
  const strong = 'Date,Workout Name,Exercise Name,Set Order,Weight,Reps,Seconds,RPE';
  const fitnotes = 'Date,Exercise,Category,Weight,Reps,Distance,Distance Unit,Time';

  ImportResult rows(String head, List<String> lines, {String unit = 'kg'}) =>
      parseWorkoutCSV([head, ...lines].join('\n'), unit: unit);

  /// Every set of every workout, in file order.
  List<SetLog> setsOf(ImportResult p) =>
      [for (final w in p.workouts) for (final e in w.entries) ...e.sets];

  group('the CSV reader itself', () {
    test('handles quoted fields, embedded commas and doubled quotes', () {
      final r = parseCSV('a,b\n"Bench Press, Close Grip","he said ""hi"""');
      expect(r, hasLength(2));
      expect(r[1], ['Bench Press, Close Grip', 'he said "hi"']);
    });

    test('handles CRLF and a byte-order mark', () {
      final r = parseCSV('﻿Date,Exercise\r\n2026-01-12,Squat\r\n');
      expect(r.first, ['Date', 'Exercise']);
      expect(r[1], ['2026-01-12', 'Squat']);
    });

    test('drops blank lines rather than importing empty rows', () {
      expect(parseCSV('a,b\n\n\nc,d'), hasLength(2));
    });
  });

  group('source detection', () {
    test('names the app a header came from', () {
      expect(detectSource(parseCSV(hevy).first), 'Hevy');
      expect(detectSource(parseCSV(strong).first), 'Strong');
      expect(detectSource(parseCSV(fitnotes).first), 'FitNotes');
      expect(detectSource(['Date', 'Exercise', 'Weight']), isNull);
    });
  });

  group('dates', () {
    test('reads every dialect the exporters write', () {
      expect(parseWhen('2020-12-30 18:51:52')?.d, '2020-12-30');
      expect(parseWhen('2024-03-07')?.d, '2024-03-07');
      expect(parseWhen('22 Dec 2025, 08:00')?.d, '2025-12-22');
      expect(parseWhen('Dec 22, 2025')?.d, '2025-12-22');
      // Day-first when ambiguous: an unqualified numeric date came through a spreadsheet.
      expect(parseWhen('07/03/2024')?.d, '2024-03-07');
      expect(parseWhen('25/12/2024')?.d, '2024-12-25');
      expect(parseWhen('nonsense'), isNull);
    });

    test('carries the time of day where there is one', () {
      expect(parseWhen('2026-01-12 18:30')?.t, 18 * 3600000 + 30 * 60000);
      expect(parseWhen('2026-01-12')?.t, isNull);
    });
  });

  group('exercise matching', () {
    test('resolves the names people actually log', () {
      expect(matchExercise('Bench Press'), '0025');
      expect(matchExercise('Squat (Barbell)'), '0043');
      expect(matchExercise('Deadlift'), '0032');
      expect(matchExercise('Lat Pulldown'), '2330');
    });

    test('leaves an unknown name unmatched rather than guessing', () {
      expect(matchExercise('Sandbag Zercher Carry Thing'), isNull);
      expect(matchExercise(''), isNull);
      expect(matchExercise(null), isNull);
    });
  });

  group('importing effort from another app', () {
    test('reads the RPE Hevy writes per set', () {
      final p = rows(hevy, [
        'Push,"12 Jan 2026, 18:00","12 Jan 2026, 19:00",Bench Press (Barbell),0,normal,60,10,8',
        'Push,"12 Jan 2026, 18:00","12 Jan 2026, 19:00",Bench Press (Barbell),1,normal,60,8,9.5',
      ]);
      expect(p.error, isNull);
      expect(setsOf(p).map((s) => s.rpe), [8, 9.5]);
      expect(p.rpeSets, 2);
      expect(p.rirSets, 0);
    });

    test('reads the RPE Strong writes per set', () {
      final p = rows(strong, ['2026-01-12 18:00:00,Push,Bench Press (Barbell),1,60,10,0,7.5']);
      expect(setsOf(p).first.rpe, 7.5);
      expect(p.rpeSets, 1);
    });

    test('reads an RIR column when a file has one', () {
      final p = rows('Date,Exercise,Weight,Reps,RIR', [
        '2026-01-12,Bench Press,60,10,2',
        // 0 RIR is a real rating: taken to failure.
        '2026-01-12,Bench Press,60,6,0',
      ]);
      expect(setsOf(p).map((s) => s.rir), [2, 0]);
      expect(p.rirSets, 2);
      expect(setsOf(p).every((s) => s.rpe == null), isTrue);
    });

    test('treats a blank rating as not rated, not as zero', () {
      final p = rows(hevy, [
        'Push,"12 Jan 2026, 18:00",,Bench Press (Barbell),0,normal,60,10,',
        'Push,"12 Jan 2026, 18:00",,Bench Press (Barbell),1,normal,60,10,8',
      ]);
      final s = setsOf(p);
      // The key is absent, so the set reads as unrated.
      expect(s[0].toJson().containsKey('rpe'), isFalse);
      expect(s[1].rpe, 8);
      expect(p.rpeSets, 1);
    });

    test('does not read a written-out 0 as an RPE', () {
      // RPE runs 1–10, so a 0 in that column is an app saying "nothing here". Reading it as a
      // rating would stamp an effort on every unrated set in the file.
      final p = rows(strong, ['2026-01-12 18:00:00,Push,Bench Press (Barbell),1,60,10,0,0']);
      expect(setsOf(p).first.toJson().containsKey('rpe'), isFalse);
      expect(p.rpeSets, 0);
    });

    test('caps a rating that overruns the scale instead of dropping the set', () {
      final p = rows(strong, ['2026-01-12 18:00:00,Push,Bench Press (Barbell),1,60,10,0,12']);
      expect(setsOf(p).first.rpe, 10);
    });

    test('ignores junk in the rating column', () {
      final p = rows(strong, [
        '2026-01-12 18:00:00,Push,Bench Press (Barbell),1,60,10,0,hard',
        '2026-01-12 18:00:00,Push,Bench Press (Barbell),2,60,10,0,-3',
      ]);
      expect(setsOf(p).every((s) => !s.toJson().containsKey('rpe')), isTrue);
      expect(p.rpeSets, 0);
      // The sets still import, just unrated.
      expect(p.sets, 2);
    });

    test('keeps one scale per set when a file carries both columns', () {
      final p = rows('Date,Exercise,Weight,Reps,RPE,RIR', ['2026-01-12,Bench Press,60,10,8,2']);
      final s = setsOf(p).first;
      expect(s.rir, 2);
      expect(s.toJson().containsKey('rpe'), isFalse);
      // ...and it reads back on the scale it was stored with.
      expect(setLabel('0025', s), '60×10 (RIR 2)');
    });

    test('puts no effort on a cardio row', () {
      // A treadmill row has no third stepper to show it in.
      final p = rows('Date,Exercise,Distance,Distance Unit,Time,RPE',
          ['2026-01-12,Running,5,km,00:30:00,7']);
      final s = setsOf(p).first;
      expect(s.min, 30);
      expect(s.toJson().containsKey('rpe'), isFalse);
      expect(p.rpeSets, 0);
    });

    test('leaves a file without any rating column exactly as it was', () {
      final p = rows(fitnotes, ['2026-01-12,Bench Press,Chest,60,10,,,']);
      expect(setsOf(p).first.toJson(), {'w': 60, 'r': 10, 'done': true});
      expect(p.rpeSets + p.rirSets, 0);
    });

    test('carries the rating through the unit conversion', () {
      // lb -> kg rewrites the weight; the rating must survive that pass untouched.
      final p = parseWorkoutCSV(
        ['Date,Exercise,Weight,Weight Unit,Reps,RPE', '2026-01-12,Bench Press,135,lbs,10,8']
            .join('\n'),
        unit: 'kg',
      );
      final s = setsOf(p).first;
      expect(s.w, 61.2);
      expect(s.rpe, 8);
      // The row's unit marker never reaches the stored set.
      expect(s.toJson().keys, ['w', 'r', 'done', 'rpe']);
    });
  });

  group('units', () {
    test('converts per row, so a mixed-unit history is not taken over as-is', () {
      final p = rows('Date,Exercise,Weight,Weight Unit,Reps', [
        '2026-01-12,Bench Press,135,lbs,10',
        '2026-01-12,Bench Press,60,kg,10',
      ]);
      expect(p.mixedUnits, isTrue);
      expect(setsOf(p).map((s) => s.w), [61.2, 60]);
    });

    test('a file that says nothing is taken to be in the profile’s unit already', () {
      final p = rows('Date,Exercise,Weight,Reps', ['2026-01-12,Bench Press,60,10']);
      expect(p.fileUnit, '');
      expect(p.converted, isFalse);
      expect(setsOf(p).first.w, 60);
    });
  });

  group('what a file amounts to', () {
    test('counts distinct exercises matched, not rows', () {
      final p = rows(fitnotes, [
        '2026-01-12,Bench Press,Chest,60,10,,,',
        '2026-01-12,Bench Press,Chest,60,10,,,',
        '2026-01-12,Squat,Legs,100,5,,,',
      ]);
      expect(p.matched, 2);
      expect(p.matchedSets, 3);
      expect(p.sets, 3);
    });

    test('invents an exercise for a name it cannot resolve, and says which', () {
      final p = rows(fitnotes, ['2026-01-12,Sandbag Zercher Carry Thing,Legs,40,10,,,']);
      expect(p.created, 1);
      expect(p.unmatchedNames, ['Sandbag Zercher Carry Thing']);
      expect(p.customEx.first.bp, 'upper legs');
    });

    test('reports an unreadable file rather than importing nothing silently', () {
      expect(parseWorkoutCSV('').error, 'empty');
      expect(parseWorkoutCSV('a,b\n1,2').error, 'unrecognised');
    });

    test('skips rows with nothing measured in them', () {
      final p = rows(fitnotes, [
        '2026-01-12,Bench Press,Chest,60,10,,,',
        '2026-01-12,Bench Press,Chest,,,,,',
      ]);
      expect(p.sets, 1);
      expect(p.skipped, 1);
    });
  });

  group('body weight', () {
    test('pulls body-mass records out of an Apple Health export', () {
      const xml = '''
<HealthData>
  <Record type="HKQuantityTypeIdentifierStepCount" value="8000" startDate="2026-01-10 08:00:00 +0000"/>
  <Record type="HKQuantityTypeIdentifierBodyMass" unit="kg" value="80.5" startDate="2026-01-10 08:00:00 +0000"/>
  <Record type="HKQuantityTypeIdentifierBodyMass" unit="kg" value="79.8" startDate="2026-01-17 08:00:00 +0000"/>
</HealthData>''';
      final p = parseImport(xml);
      expect(p.isBodyweight, isTrue);
      expect(p.bodyweight.map((b) => b.w), [80.5, 79.8]);
      expect(p.from, '2026-01-10');
      expect(p.to, '2026-01-17');
    });

    test('converts pounds out of Health into the profile’s kilograms', () {
      const xml =
          '<Record type="HKQuantityTypeIdentifierBodyMass" unit="lb" value="180" startDate="2026-01-10"/>';
      final p = parseImport(xml);
      expect(p.converted, isTrue);
      expect(p.bodyweight.first.w, 81.6);
    });

    test('reads a plain weight CSV too', () {
      final p = parseImport('Date,Weight\n2026-01-10,80.5\n2026-01-17,79.8');
      expect(p.isBodyweight, isTrue);
      expect(p.bodyweight, hasLength(2));
    });
  });

  group('merging', () {
    test('existing days win, so importing twice never duplicates a workout', () {
      final p = rows(fitnotes, ['2026-01-12,Bench Press,Chest,60,10,,,']);
      final s = AppState.defaults();

      final first = mergeImport(s, p);
      expect(first.added, 1);
      expect(s.workouts, hasLength(1));

      final again = mergeImport(s, p);
      expect(again.added, 0);
      expect(again.skipped, 1);
      expect(s.workouts, hasLength(1));
    });

    test('an imported history seeds the weight suggestions', () {
      final p = rows(fitnotes, ['2026-01-12,Bench Press,Chest,60,10,,,']);
      final s = AppState.defaults();
      mergeImport(s, p);
      expect(s.exWeights['0025']?.w, 60);
    });

    test('imported workouts survive a backup round trip', () {
      final p = rows(hevy, [
        'Push,"12 Jan 2026, 18:00","12 Jan 2026, 19:00",Bench Press (Barbell),0,normal,60,10,8',
      ]);
      final s = AppState.defaults();
      mergeImport(s, p);
      final back = AppState.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
      expect(back.workouts.first.entries.first.sets.first.rpe, 8);
      expect(setLabel('0025', back.workouts.first.entries.first.sets.first), '60×10 (RPE 8)');
    });
  });
}
