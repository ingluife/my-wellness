import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/domain/ai/meal_photo_prompt.dart';
import 'package:my_wellness/domain/foods.dart';
import 'package:my_wellness/domain/i18n.dart';

/// The vocabulary block is the cached prefix of every meal-photo request.
///
/// Almost everything that can go wrong with it is invisible at runtime: the app keeps working,
/// the answers stay fine, and the only symptom is that the cache never hits and each photo costs
/// several times what it should. These tests are the only place that failure is visible.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await foods.load();
  });

  tearDown(() async => I18n.instance.setLang('en'));

  test('every catalogue food appears exactly once, with its id', () {
    final v = buildVocabulary(foods.db);
    for (final f in foods.db) {
      expect(RegExp('^${f.id} ', multiLine: true).allMatches(v), hasLength(1),
          reason: '${f.id} (${f.n}) should appear exactly once');
    }
  });

  test('it is byte-identical when built twice', () {
    expect(buildVocabulary(foods.db), buildVocabulary(foods.db));
  });

  test('changing the app language does not change one byte of it', () async {
    // The block carries English names on purpose: the ids are what come back, so translating it
    // buys nothing — and would rebuild the cached prefix every time somebody switched language,
    // which nothing in the app would ever report.
    final english = buildVocabulary(foods.db);
    await I18n.instance.setLang('es');
    expect(t('Chicken breast'), isNot('Chicken breast'),
        reason: 'sanity: the Spanish pack really did load');
    expect(buildVocabulary(foods.db), english);
  });

  test('it stays inside a size budget', () {
    // A column per row is the tempting change, and it roughly doubles the prefix. The budget is
    // here so that change has to be made deliberately.
    final v = buildVocabulary(foods.db);
    expect(v.length, lessThan(8000),
        reason: 'the vocabulary has grown a lot — is it still one id and one name per line?');
  });

  test('it is grouped by category, in catalogue order', () {
    final v = buildVocabulary(foods.db);
    final headers = RegExp(r'^# (\w+)$', multiLine: true)
        .allMatches(v)
        .map((m) => m.group(1))
        .toList();
    expect(headers, isNotEmpty);
    // Categories appear in the order the catalogue declares, and none twice.
    expect(headers, equals(headers.toSet().toList()));
    for (final h in headers) {
      expect(foodCategories, contains(h));
    }
  });

  group('the volatile tail', () {
    test("a user's own foods are not in the cached block", () {
      // They belong after the breakpoint. In the prefix they would invalidate the cache every
      // time somebody added a food.
      final v = buildVocabulary(foods.db);
      expect(v, isNot(contains('cf1')));
      expect(v, isNot(contains('My protein shake')));
    });

    test('custom foods are listed most recent first, and capped', () {
      final many = [
        for (var i = 0; i < 100; i++) CustomFood(id: 'cf$i', n: 'Food $i'),
      ];
      final block = buildCustomFoods(many, cap: 60);
      final lines = block.split('\n');
      expect(lines, hasLength(60));
      expect(lines.first, 'cf99 Food 99');
    });

    test('no custom foods produces nothing at all, not an empty heading', () {
      expect(buildCustomFoods(const []), isEmpty);
    });

    test('the tail carries the language, the custom foods and the hint', () {
      final tail = buildRequestTail(
        languageName: 'Spanish',
        customFoods: 'cf1 My protein shake',
        hint: '  the rice is a big portion  ',
      );
      expect(tail, contains('Spanish'));
      expect(tail, contains('cf1 My protein shake'));
      expect(tail, contains('the rice is a big portion'));
    });

    test('an absent hint leaves no dangling label', () {
      final tail = buildRequestTail(languageName: 'English');
      expect(tail, isNot(contains('said about')));
      expect(tail.trim(), tail);
    });
  });

  group('the schema', () {
    test('it carries no bound the constrained-decoding subset would reject', () {
      // minimum / maximum / minLength / maxItems are all unsupported and would be a 400. Every
      // bound lives in the sanitizer instead, where it is unit-tested.
      final rendered = mealPhotoSchema.toString();
      for (final unsupported in const [
        'minimum', 'maximum', 'minItems', 'maxItems', 'minLength', 'maxLength', 'multipleOf',
      ]) {
        expect(rendered, isNot(contains(unsupported)));
      }
    });

    test('it never asks for a total the app is going to throw away', () {
      // For a catalogue hit the macros come from USDA. A total in the schema would spend output
      // tokens on a number that gets discarded, and leave a field for someone to start trusting.
      final item = (mealPhotoSchema['properties'] as Map)['items'] as Map;
      final props = ((item['items'] as Map)['properties'] as Map).keys.toSet();
      expect(props, isNot(contains('kcal')));
      expect(props, isNot(contains('calories')));
      expect(props, containsAll(['fid', 'name', 'grams', 'per100']));
    });

    test('every object closes itself to extra properties', () {
      void walk(Map<String, dynamic> node) {
        if (node['type'] == 'object') {
          expect(node['additionalProperties'], isFalse,
              reason: 'strict decoding requires additionalProperties: false on every object');
        }
        for (final v in node.values) {
          if (v is Map<String, dynamic>) walk(v);
        }
      }

      walk(mealPhotoSchema);
    });
  });
}
