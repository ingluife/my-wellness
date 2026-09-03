import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/domain/ai/plan_prompt.dart';
import 'package:my_wellness/domain/ai/plan_scope.dart';
import 'package:my_wellness/domain/exercises.dart';

import 'helpers.dart';

/// The catalogue block, and the size guards that keep this feature affordable.
///
/// The size assertions are the point of this file. Sending the dataset as it sits on disk is
/// ~240,000 tokens — over a dollar of input per call on the largest model offered, and more
/// context than several of them have. The projection and the scope filter bring that to a few
/// thousand, and nothing about that is enforced by the type system: one extra field in
/// [buildExerciseCatalogue] would multiply the bill for every user with no test going red and no
/// symptom until a statement arrives.
void main() {
  setUpAll(loadExercises);

  /// Tokens, near enough. The block is terse ASCII with a lot of short words, which runs a little
  /// under four characters a token; 3.7 is the ratio the cost analysis was done at.
  double tokensOf(String s) => s.length / 3.7;

  String blockFor(PlanScope scope) =>
      buildExerciseCatalogue(exercisesInScope(scope));

  group('the projection', () {
    test('carries what a choice needs, and nothing else', () {
      final line = blockFor(const PlanScope.target('biceps'))
          .split('\n')
          .firstWhere((l) => !l.startsWith('#'));

      // id, name, target, equipment — four fields, three separators.
      expect(line.split(' | '), hasLength(3));
      expect(RegExp(r'^\d{4} ').hasMatch(line), isTrue, reason: line);
    });

    test('never carries the instructions, which are 72% of the dataset', () {
      // The single biggest cost decision in the feature. `st` averages 5.8 steps per exercise and
      // is 635 KB of the 888 KB file; the app already renders it locally from the same asset, so
      // sending it would be paying to tell the model something the user can already read.
      final block = blockFor(const PlanScope.target('biceps'));
      final curl = exdb.db.firstWhere((e) => e.id == '0031');

      expect(block, contains('0031'));
      expect(block, isNot(contains(curl.st.first)));
      // Nor the media filenames, which are pure cost.
      expect(block, isNot(contains('.gif')));
      expect(block, isNot(contains('.jpg')));
    });

    test('groups by body part so a full-body block reads as a library', () {
      final block = blockFor(const PlanScope.fullBody());
      expect(block, contains('# upper arms'));
      expect(block, contains('# chest'));
      // Cardio and neck are not part of a general plan — see _excludedBp.
      expect(block, isNot(contains('# cardio')));
      expect(block, isNot(contains('# neck')));
    });
  });

  group('size guards', () {
    test('a full-body block stays near 19k tokens, not 240k', () {
      final t = tokensOf(blockFor(const PlanScope.fullBody()));
      expect(t, lessThan(24000),
          reason: 'the whole projected library; a regression here is the whole bill');
      expect(t, greaterThan(12000), reason: 'suspiciously small — is the filter dropping too much?');
    });

    test('a muscle-group block stays a fraction of the full library', () {
      // The scope filter is what makes a targeted request cheap. If any of these ever approaches
      // the full-body figure, the filter has stopped filtering.
      //
      // The ceiling is 8k rather than the ~2.4k a `tg`-only match would give, and the difference
      // is [TargetScope] admitting secondary work on purpose. It is the right trade: `tg ==
      // 'hamstrings'` is 28 exercises, and every deadlift in the library is tagged `glutes` with
      // hamstrings secondary — a hamstring day built without them would be leg curls and nothing
      // else. Triceps is the widest at ~6.3k.
      for (final tg in ['biceps', 'triceps', 'hamstrings', 'glutes']) {
        expect(tokensOf(blockFor(PlanScope.target(tg))), lessThan(8000), reason: tg);
      }
      expect(tokensOf(blockFor(const PlanScope.bodyPart('chest'))), lessThan(4000));
      expect(tokensOf(blockFor(const PlanScope.bodyPart('upper arms'))), lessThan(6000));
    });

    test('the instructions and schema overhead stay small beside the catalogue', () {
      final brief = PlanBrief(
        scope: const PlanScope.target('biceps'),
        daysPerWeek: 4,
        sessionMinutes: 60,
        experience: 'training for a while',
        goal: 'build muscle',
      );
      final req = planRequest(
        brief: brief,
        catalogue: exercisesInScope(brief.scope),
        languageName: 'English',
      );
      final overhead = tokensOf(planInstructions) + tokensOf(req.systemTail);
      expect(overhead, lessThan(1500));
    });
  });

  group('scope', () {
    test('a target scope admits secondary work, not just the prime mover', () {
      // Somebody asking for a biceps day means chin-ups and rows too. Filtering on `tg` alone
      // would hand back nothing but curls.
      final ids = exercisesInScope(const PlanScope.target('biceps')).map((e) => e.id).toSet();
      final secondary =
          exdb.db.where((e) => e.tg != 'biceps' && e.sm.contains('biceps')).map((e) => e.id);
      expect(secondary, isNotEmpty);
      expect(ids, containsAll(secondary));
    });

    test('a body-part scope is exactly that body part', () {
      for (final e in exercisesInScope(const PlanScope.bodyPart('chest'))) {
        expect(e.bp, 'chest');
      }
    });

    test('equipment narrows it further, and only to what was asked for', () {
      final home = exercisesInScope(
        const PlanScope.fullBody(),
        equipment: const {'body weight', 'dumbbell'},
      );
      expect(home, isNotEmpty);
      for (final e in home) {
        expect(e.eq, anyOf('body weight', 'dumbbell'));
      }
      // And it genuinely cuts the bill, which is half the reason it is plumbed through.
      expect(
        buildExerciseCatalogue(home).length,
        lessThan(buildExerciseCatalogue(exercisesInScope(const PlanScope.fullBody())).length),
      );
    });

    test('the request sends no cache breakpoint', () {
      // The considered opposite of the meal photo, and the note in plan_prompt.dart explains it:
      // a plan is drafted once and not again for weeks, so every call would pay the 1.25x write
      // and none would ever read it — about 7x worse than simply sending the scoped block.
      final req = planRequest(
        brief: PlanBrief(
          scope: const PlanScope.fullBody(),
          daysPerWeek: 3,
          sessionMinutes: 60,
          experience: 'new to training',
        ),
        catalogue: exercisesInScope(const PlanScope.fullBody()),
        languageName: 'English',
      );
      expect(req.cachePrefix, isFalse);
      expect(req.jpeg, isNull, reason: 'a text-only feature must not carry an image part');
    });
  });
}
