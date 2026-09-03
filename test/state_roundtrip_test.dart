import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/data/ai/ai_key_store.dart';
import 'package:my_wellness/data/models/app_state.dart';

/// The single most important test in the project.
///
/// My Wellness and openGym have to read each other's backups, which means the Dart models must
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

  // Nutrition is the first feature with state openGym has no default for. It has to stay
  // invisible until it is used: openGym overlays a loaded state on DEF, so a key it does not
  // know is carried through untouched, but a key this build writes into *every* export would
  // show up as a diff against a fresh openGym backup forever after.
  group('nutrition', () {
    final withNutrition = jsonDecode(
      File('test/fixtures/nutrition_state.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    test('a state carrying nutrition and meals survives the round trip unchanged', () {
      final out = AppState.fromJson(withNutrition).toJson();
      expect(jsonDecode(jsonEncode(out)), equals(withNutrition));
    });

    test('an untouched profile writes neither key', () {
      final out = AppState.defaults().toJson();
      expect(out.containsKey('nutrition'), isFalse);
      expect(out.containsKey('meals'), isFalse);
    });

    test('the fixture without them still writes neither', () {
      // The guard that matters: reading a backup from openGym and exporting it again must not
      // grow keys that were never there.
      final out = AppState.fromJson(source).toJson();
      expect(out.containsKey('nutrition'), isFalse);
      expect(out.containsKey('meals'), isFalse);
    });

    test('a meal logged by hand carries no photo key', () {
      // `photo` is a fourth key openGym has no default for, under the same absent-until-used
      // contract as the three above it — and most meals are logged by hand, so most meals must
      // serialise exactly as they did before the field existed.
      final s = AppState.defaults();
      s.meals.add(Meal(
        id: 'ml1',
        d: '2026-08-27',
        items: [MealItem(n: 'Toast', g: 40, kcal: 100, p: 3, c: 20, f: 1)],
      ));
      expect((s.toJson()['meals'] as List).single, isNot(contains('photo')));

      s.meals.single.photo = 'mpabc123.jpg';
      final out = AppState.fromJson(s.toJson());
      expect(out.meals.single.photo, 'mpabc123.jpg');
      // ...and it deep-clones, so the boot sweep clearing it on a draft cannot reach back into
      // the state the UI is still reading.
      final clone = out.copy();
      clone.meals.single.photo = null;
      expect(out.meals.single.photo, 'mpabc123.jpg');
    });

    test('setting one field is enough to start writing the key', () {
      final s = AppState.defaults();
      s.nutrition.profile.age = 34;
      expect(s.toJson()['nutrition'], {
        'profile': {'age': 34},
      });
      // ...and clearing it again drops the key rather than leaving an empty object behind.
      s.nutrition.profile.age = null;
      expect(s.toJson().containsKey('nutrition'), isFalse);
    });

    test('a goal set to what happens to be the default is still recorded', () {
      // Mirrors `effort`: null means never chose, so an explicit choice has to survive even
      // when it matches the value the app would have assumed anyway.
      final s = AppState.defaults();
      s.nutrition.goal.mode = 'maintain';
      expect(s.toJson()['nutrition'], {
        'goal': {'mode': 'maintain'},
      });
    });

    test('meal macros are stored, not recomputed from the catalog', () {
      final s = AppState.fromJson(withNutrition);
      final item = s.meals.first.items.first;
      expect(item.fid, 'f0142');
      expect(item.kcal, 216);
      // The totals a day reads come from the logged numbers, so regenerating foods.json can
      // never rewrite what last month says you ate.
      expect(s.meals.first.kcal, 336);
      expect(s.meals.first.p, closeTo(46.9, 1e-9));
    });

    test('saved meals and a dismissed suggestion round-trip too', () {
      final s = AppState.fromJson(withNutrition);
      expect(s.nutrition.templates, hasLength(2));
      expect(s.nutrition.templates.first.n, 'Usual breakfast');
      expect(s.nutrition.templates.first.used, 12);
      // The second was saved and never used: absent counts stay absent, not zeroed.
      expect(s.nutrition.templates[1].used, isNull);
      expect(s.nutrition.templates[1].toJson().containsKey('used'), isFalse);
      expect(s.nutrition.dismissedAdj, 1741000000000);
    });

    test('saving a meal is enough to start writing the key, and clearing it stops', () {
      final s = AppState.defaults();
      expect(s.toJson().containsKey('nutrition'), isFalse);

      s.nutrition.templates.add(MealTemplate(id: 'mt1', n: 'x'));
      expect(s.toJson()['nutrition'], {
        'templates': [
          {'id': 'mt1', 'n': 'x', 'items': <dynamic>[]},
        ],
      });

      s.nutrition.templates.clear();
      expect(s.toJson().containsKey('nutrition'), isFalse);
    });

    test('turning down a suggestion is on its own enough to persist', () {
      // It has to be: a dismissal that vanished on restart would mean the same suggestion
      // came back every time the app opened.
      final s = AppState.defaults();
      s.nutrition.dismissedAdj = 1741000000000;
      expect(s.toJson()['nutrition'], {'dismissedAdj': 1741000000000});
    });

    test('the deep clone reaches into meals', () {
      final s = AppState.fromJson(withNutrition);
      final clone = s.copy();
      clone.meals.first.items.first.kcal = 999;
      clone.nutrition.profile.age = 99;
      clone.nutrition.templates.first.items.first.kcal = 999;
      expect(s.meals.first.items.first.kcal, 216);
      expect(s.nutrition.profile.age, 34);
      expect(s.nutrition.templates.first.items.first.kcal, 215);
    });
  });

  // `ai` is the third key openGym has no default for, under the same contract as nutrition and
  // meals. The tests below are the nutrition ones again, plus one that has nothing to do with the
  // round trip and everything to do with what must never be in it.
  group('ai', () {
    test('an untouched profile writes no ai key', () {
      expect(AppState.defaults().toJson().containsKey('ai'), isFalse);
    });

    test('the openGym fixture still writes none', () {
      // The guard that matters: reading a backup from openGym and exporting it again must not
      // grow a key that was never there.
      final out = AppState.fromJson(source).toJson();
      expect(out.containsKey('ai'), isFalse);
    });

    test('merely looking at a feature does not start writing the key', () {
      // `feature()` creates on demand so callers can write to it directly. That is only safe
      // while a fresh config is indistinguishable from no config at all.
      final s = AppState.defaults();
      s.ai.feature(aiMealPhoto);
      expect(s.toJson().containsKey('ai'), isFalse);
    });

    test('turning the feature on is enough to start writing it, and off again drops it', () {
      final s = AppState.defaults();
      s.ai.feature(aiMealPhoto).on = true;
      expect(s.toJson()['ai'], {
        'mealPhoto': {'on': true},
      });

      s.ai.feature(aiMealPhoto).on = null;
      expect(s.toJson().containsKey('ai'), isFalse);
    });

    test('a choice that happens to match the default is still recorded', () {
      // Mirrors `effort` and the nutrition goal: null means never chose, so an explicit "off"
      // has to survive even though off is what the app would have assumed anyway.
      final s = AppState.defaults();
      s.ai.feature(aiMealPhoto).on = false;
      expect(s.toJson()['ai'], {
        'mealPhoto': {'on': false},
      });
    });

    test('a feature key from a newer build is carried through untouched', () {
      final j = {...source, 'ai': {'mealPhoto': {'on': true}, 'mealChat': {'provider': 'x'}}};
      final out = AppState.fromJson(j).toJson();
      expect(out['ai'], {
        'mealPhoto': {'on': true},
        'mealChat': {'provider': 'x'},
      });
    });

    test('keeping photos is only written once it is turned off', () {
      // The one field here that defaults to yes, so an untouched profile must still write nothing
      // and a deliberate "no" must survive a round trip rather than being read back as never
      // chosen — which is exactly how the setting would fail to stay off.
      final s = AppState.defaults();
      expect(s.ai.feature(aiMealPhoto).keepsPhotos, isTrue);
      expect(s.toJson().containsKey('ai'), isFalse);

      s.ai.feature(aiMealPhoto).keepPhotos = false;
      expect(s.toJson()['ai'], {
        'mealPhoto': {'keepPhotos': false},
      });
      expect(AppState.fromJson(s.toJson()).ai.feature(aiMealPhoto).keepsPhotos, isFalse);
    });

    test('the deep clone reaches into ai settings', () {
      final s = AppState.defaults();
      // `model` needs a provider to file itself under now — see AiFeatureConfig.models.
      s.ai.feature(aiMealPhoto)
        ..provider = 'anthropic'
        ..model = 'claude-opus-5';
      final clone = s.copy();
      clone.ai.feature(aiMealPhoto).model = 'something-else';
      expect(s.ai.feature(aiMealPhoto).model, 'claude-opus-5');
    });

    test('no API key can reach the exported state', () async {
      // This cannot fail today: AiSettings has nowhere to put a key, which is the entire design.
      // It is written down so that the next person who adds a "convenience" field to it trips
      // over the reason rather than rediscovering it after a backup has been emailed around.
      const sentinel = 'sk-ant-SENTINEL-must-never-be-serialised';
      final store = MemoryAiKeyStore();
      await store.write('anthropic', sentinel);

      final s = AppState.defaults();
      s.ai.feature(aiMealPhoto)
        ..on = true
        ..provider = 'anthropic'
        ..model = 'claude-opus-5';

      expect(await store.read('anthropic'), sentinel);
      expect(jsonEncode(s.toJson()), isNot(contains(sentinel)));
      expect(jsonEncode(s.toJson()), isNot(contains('sk-ant')));
    });
  });
}
