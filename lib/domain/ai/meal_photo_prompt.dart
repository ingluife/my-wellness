import 'dart:typed_data';

import '../../data/models/app_state.dart';
import '../foods.dart';
import 'ai_provider.dart';

/// What the model is asked, and the vocabulary it is asked to answer in.
///
/// The shape of this file is the design of the whole feature. The model is **never** asked for
/// calories. It is asked to name what it sees using ids the app already has USDA figures for, and
/// to estimate weight in grams — the two things a photograph can actually support. The app does
/// the arithmetic afterwards through `Food.portion`, which is the same code path a hand-logged
/// food takes, so the numbers in the log stay traceable to a food record rather than to a
/// sentence a model produced.

/// The catalogue block, grouped by category.
///
/// Three properties matter, and each is a real bug if lost:
///
///  1. **Built from the bundled catalogue in file order** — never `foods.all(state)`, which puts
///     the user's own foods first and would change this text every time they add one.
///  2. **English names only** — never `t(name)`. The ids are what come back, so translating this
///     buys nothing and would rebuild the block on every language change.
///  3. **Stable across runs**, because it is the cached prefix of every request. Anything volatile
///     belongs in [buildCustomFoods], which is sent *after* the cache breakpoint.
String buildVocabulary(List<Food> catalogue) {
  final byCat = <String, List<Food>>{};
  for (final f in catalogue) {
    (byCat[f.cat] ??= []).add(f);
  }
  final b = StringBuffer();
  for (final cat in foodCategories) {
    final list = byCat[cat];
    if (list == null || list.isEmpty) continue;
    b.writeln('# $cat');
    for (final f in list) {
      b.writeln('${f.id} ${f.n}');
    }
  }
  return b.toString().trimRight();
}

/// The user's own foods, as a second block.
///
/// Capped and most-recent-first: these are the foods this person actually eats, so they earn a
/// place in the prompt, but there can be hundreds of them and they change often. Keeping them out
/// of [buildVocabulary] is what lets the catalogue half stay cacheable.
String buildCustomFoods(List<CustomFood> foods, {int cap = 60}) {
  if (foods.isEmpty) return '';
  final b = StringBuffer();
  for (final f in foods.reversed.take(cap)) {
    b.writeln('${f.id} ${f.n}');
  }
  return b.toString().trimRight();
}

/// The instruction half of the system prompt — everything before the vocabulary.
///
/// English, and not translated: it is not user-facing, and the language the *answer* should come
/// back in is stated separately, after the cache breakpoint, so switching the app's language does
/// not invalidate the cached prefix.
const mealPhotoInstructions = '''
You identify the food in a photograph of a meal and estimate how much of each is there.

Return one entry per distinguishable food, using this catalogue where it genuinely applies:

- Set "fid" to a catalogue id only when that entry is the *same food* as what you see. A different
  preparation of the same ingredient is the same food — grilled, boiled and roast chicken are all
  chicken. A dish that merely resembles a catalogue entry, or is made of it, is not: a filled
  pastry is not flour, and an arepa is not a tortilla.
- When nothing in the catalogue is that food, leave "fid" empty and give "per100" — macros per
  100 g — together with "cat", the category it belongs in. A food the catalogue does not have is a
  normal answer, not a failure, and naming it as itself is far more useful than forcing it onto a
  near-neighbour. Never give "per100" alongside an "fid".
- Set "match" on every entry: "same" when the "fid" is genuinely that food, "new" when there is no
  "fid". If you would have to explain the difference to the person eating it, it is "new".
- Always set "name" to what you would call the food, even when you set an "fid". If the two
  disagree the reviewer needs to see both.

Estimating weight:

- "grams" is edible weight as served — no bones, shells, packaging or inedible skin.
- Say what you used for scale in "note" when you can: a dinner plate is roughly 26 cm, a fork
  about 19 cm, a standard drink can 33 cl.
- "gramsLow" and "gramsHigh" bound a plausible range for that portion. Make the range as wide as
  the photograph genuinely leaves it, not as narrow as you can defend.
- Include cooking fat, oil, dressing or sauce as its own entry only when you can actually see
  evidence of it. Do not add a spoon of oil to every cooked dish on principle.

If the photograph is not of food, set "notFood" to true and return no items.

Set "confidence" for the reading as a whole: "high" only when the foods are unambiguous and the
portions have something to scale against.
''';

/// The response schema.
///
/// Deliberately carries no `minimum` / `maximum` / `maxItems`: the constrained-decoding subset
/// rejects them, so every bound lives in `meal_photo_sanitize.dart` where it is unit-tested. This
/// schema constrains *shape*; Dart constrains *values*.
///
/// And deliberately no total kcal/p/c/f. For a catalogue hit the app computes them and would
/// throw the model's away, so asking for them spends output tokens on numbers that get discarded
/// — and leaves a field there for a future reader to "helpfully" start trusting.
const mealPhotoSchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['items', 'confidence'],
  'properties': {
    'notFood': {'type': 'boolean'},
    'confidence': {
      'type': 'string',
      'enum': ['high', 'medium', 'low'],
    },
    'items': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['name', 'grams', 'match'],
        'properties': {
          'fid': {'type': 'string'},
          // Whether the "fid" is the same food or only a near neighbour. Required, so a provider
          // doing constrained decoding always answers it rather than leaving the sanitizer to
          // guess — and `meal_photo_sanitize.dart` throws the id away for anything but 'same'.
          'match': {
            'type': 'string',
            'enum': ['same', 'new'],
          },
          'name': {'type': 'string'},
          // Only meaningful for a 'new' food: it prefills the category on the "save this as one of
          // your foods" form. The enum is the app's own list, not a copy of it.
          'cat': {
            'type': 'string',
            'enum': foodCategories,
          },
          'grams': {'type': 'number'},
          'gramsLow': {'type': 'number'},
          'gramsHigh': {'type': 'number'},
          'per100': {
            'type': 'object',
            'additionalProperties': false,
            'required': ['kcal', 'p', 'c', 'f'],
            'properties': {
              'kcal': {'type': 'number'},
              'p': {'type': 'number'},
              'c': {'type': 'number'},
              'f': {'type': 'number'},
            },
          },
          'note': {'type': 'string'},
        },
      },
    },
  },
};

/// The volatile tail of the prompt: everything that may differ between two requests.
///
/// Sent as its own block *after* the cache breakpoint. Anything here that drifted into the
/// cached prefix would silently stop the prefix from ever being reused.
String buildRequestTail({
  required String languageName,
  String customFoods = '',
  String? hint,
}) {
  final b = StringBuffer();
  b.writeln('Write every "name" in $languageName.');
  if (customFoods.isNotEmpty) {
    b
      ..writeln()
      ..writeln("This person's own foods — use one of these ids only when the photo shows that "
          'same food:')
      ..writeln(customFoods);
  }
  if (hint != null && hint.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('What they said about this meal: ${hint.trim()}');
  }
  return b.toString().trimRight();
}

/// Everything above, assembled into the request an adapter sends.
///
/// The composition lives here rather than in the three adapters because the exact bytes are this
/// feature's business: the `<catalogue>` tags, which half carries the breakpoint, and the order
/// of the two blocks are all part of the caching design documented on [buildVocabulary] and
/// [buildRequestTail]. An adapter only decides how to render a prefix, a tail and an image into
/// its own envelope.
AiRequest mealPhotoRequest({
  required Uint8List jpeg,
  required String vocabulary,
  required String languageName,
  String customFoods = '',
  String? hint,
}) =>
    AiRequest(
      systemPrefix: '${mealPhotoInstructions.trim()}\n\n<catalogue>\n$vocabulary\n</catalogue>',
      systemTail: buildRequestTail(
        languageName: languageName,
        customFoods: customFoods,
        hint: hint,
      ),
      userText: 'Read this meal.',
      jpeg: jpeg,
      schema: mealPhotoSchema,
      schemaName: 'meal_photo',
      // Twelve items at roughly 60 tokens each, with headroom. Small on purpose: the answer is a
      // short structured list, and a large ceiling buys nothing but a longer worst case.
      answerTokens: 1500,
      // Worth it here, and one of the few places it is: people photograph three or four meals in
      // a sitting, minutes apart, so the catalogue prefix is genuinely still warm.
      cachePrefix: true,
    );
