import '../../data/models/app_state.dart';
import '../foods.dart';

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

Return one entry per distinguishable food, using this catalogue where you can:

- Set "fid" to a catalogue id whenever something in the catalogue is a reasonable match for what
  you see. Prefer a close catalogue match over inventing an entry.
- Only when nothing in the catalogue is close, leave "fid" empty and give "per100" instead —
  macros per 100 g for that food. Never give "per100" alongside an "fid".
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
        'required': ['name', 'grams'],
        'properties': {
          'fid': {'type': 'string'},
          'name': {'type': 'string'},
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
      ..writeln("This person's own foods — prefer these ids when they match:")
      ..writeln(customFoods);
  }
  if (hint != null && hint.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('What they said about this meal: ${hint.trim()}');
  }
  return b.toString().trimRight();
}
