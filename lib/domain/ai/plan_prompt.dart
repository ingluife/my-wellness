import '../exercises.dart';
import 'ai_provider.dart';
import 'plan_scope.dart';

/// What the model is asked when drafting a routine, and the vocabulary it answers in.
///
/// The shape of this file is the design of the feature, and the design is mostly about cost. The
/// dataset is 888 KB — about 240,000 tokens, over a dollar of input per call on the largest model
/// offered, and more context than several of them have. Two things bring that down to a few
/// thousand:
///
///  1. **A projection.** 72% of that file is `st`, the how-to instructions. The model is choosing
///     exercises, not teaching them, and the app already shows the steps locally from the same
///     asset. Dropping those plus the image filenames and the secondary-muscle lists leaves
///     ~19,000 tokens for the whole library — a 12x cut before anything else.
///  2. **A scope.** [PlanScope] filters before the block is built, so a biceps request pays for
///     151 exercises instead of 1,293.
///
/// The result is roughly 2,400 tokens for a muscle group and 19,000 for a full-body week, which
/// is between a fraction of a cent and eighteen cents depending on the model.
///
/// **No cache breakpoint**, and that is the deliberate opposite of `meal_photo_prompt.dart`. An
/// Anthropic cache write costs 1.25x input and the entry lives for minutes; a meal photo is one
/// of three or four in a sitting, so its catalogue prefix is still warm. A training plan is drawn
/// up once and then not again for weeks — every call would pay the write and none would ever read
/// it, which measures about 7x worse than simply sending the scoped block.

/// The catalogue block: one line per exercise, grouped by body part.
///
/// `"{id} {name} | {target} | {equipment}"`. Four fields, and each earns its place — the id is
/// what comes back, the name is what the model reasons about, and the target and equipment are
/// what it needs to build a balanced session someone can actually perform in their gym.
///
/// English names straight from the dataset, never `t(...)`: the ids are what come back, so
/// translating this buys nothing and would rebuild the block on every language change.
String buildExerciseCatalogue(List<Exercise> exercises) {
  final byBp = <String, List<Exercise>>{};
  for (final e in exercises) {
    (byBp[e.bp] ??= []).add(e);
  }
  final b = StringBuffer();
  for (final bp in byBp.keys) {
    b.writeln('# $bp');
    for (final e in byBp[bp]!) {
      b.writeln('${e.id} ${e.n} | ${e.tg} | ${e.eq}');
    }
  }
  return b.toString().trimRight();
}

/// What the app already knows about this person, so the sheet does not ask them again.
///
/// Everything here is read from state rather than typed: the goal comes from the nutrition goal
/// they already set, the frequency from workouts they already logged, the equipment from what
/// they have actually trained with. A form that re-asked all of it would be both longer and less
/// accurate than the log.
class PlanBrief {
  const PlanBrief({
    required this.scope,
    required this.daysPerWeek,
    required this.sessionMinutes,
    required this.experience,
    this.goal,
    this.age,
    this.sex,
    this.equipment = const {},
    this.note,
  });

  final PlanScope scope;
  final int daysPerWeek;
  final int sessionMinutes;

  /// 'new to training' | 'training for a while' | 'experienced'.
  final String experience;

  /// 'lose weight' | 'maintain' | 'build muscle', from the nutrition goal when one is set.
  final String? goal;
  final double? age;
  final String? sex;

  /// The `eq` values this person has actually trained with. Doubles as a catalogue filter, so an
  /// answer can only contain equipment they have.
  final Set<String> equipment;

  /// Anything they typed — 'my left shoulder is sore', 'no barbell on Fridays'.
  final String? note;
}

/// The instruction half of the system prompt.
///
/// English, and not translated: it is not user-facing. The language the *answer* comes back in is
/// stated separately, in the tail.
const planInstructions = '''
You draft strength-training routines from a fixed catalogue of exercises.

You are given a catalogue of exercises, one per line, as:
  <id> <name> | <target muscle> | <equipment>

Rules:
- Every exercise you choose MUST be one of the ids in the catalogue. Never invent an id, and
  never name an exercise that is not in it. The catalogue is already filtered to what was asked
  for and to the equipment this person has, so anything outside it is unusable.
- Order the exercises within a routine the way they should be performed: the heaviest compound
  movements first, isolation and accessory work last.
- Prescribe sets and a rep target for each. Use lower reps for heavy compound lifts and higher
  reps for isolation work.
- Do not repeat the same exercise id inside one routine.
- Give each routine a short name someone would recognise on a schedule ("Push", "Upper A",
  "Arms"). Do not number them unless the split genuinely needs it.

When asked for a full-body plan, return one routine per training day and fill in `week`, mapping
weekdays to the routine that belongs on them ("0" is Sunday, "1" Monday, through "6" Saturday).
Leave rest days out of `week` entirely. When asked for a single muscle group or body part, return
exactly one routine and omit `week`.

Keep `rationale` to one or two sentences on why the plan is shaped the way it is. It is shown to
the person once, under the draft.
''';

/// The response schema.
///
/// Deliberately carries no `minimum` / `maximum` / `maxItems`: the constrained-decoding subset
/// rejects them, so every bound lives in `plan_sanitize.dart` where it is unit-tested. This
/// schema constrains *shape*; Dart constrains *values*.
///
/// `emoji` is the routine's icon key, and the model picks from the same short list the routine
/// editor offers rather than from anything it might invent.
const planSchema = <String, dynamic>{
  'type': 'object',
  'additionalProperties': false,
  'required': ['routines'],
  'properties': {
    'routines': {
      'type': 'array',
      'items': {
        'type': 'object',
        'additionalProperties': false,
        'required': ['name', 'exercises'],
        'properties': {
          'name': {'type': 'string'},
          'emoji': {
            'type': 'string',
            'enum': ['barbell', 'dumbbell', 'pullup', 'legs', 'chest', 'back', 'arms', 'core'],
          },
          'exercises': {
            'type': 'array',
            'items': {
              'type': 'object',
              'additionalProperties': false,
              'required': ['id', 'sets', 'reps'],
              'properties': {
                'id': {'type': 'string'},
                'sets': {'type': 'number'},
                'reps': {'type': 'number'},
                'repsMin': {'type': 'number'},
                'repsMax': {'type': 'number'},
                'note': {'type': 'string'},
              },
            },
          },
        },
      },
    },
    // Written out rather than generated in a loop: a const map cannot carry a `for` element, and
    // this schema is a const so it is built once instead of on every request.
    'week': {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        '0': {'type': 'number'},
        '1': {'type': 'number'},
        '2': {'type': 'number'},
        '3': {'type': 'number'},
        '4': {'type': 'number'},
        '5': {'type': 'number'},
        '6': {'type': 'number'},
      },
    },
    'rationale': {'type': 'string'},
  },
};

/// The volatile tail: who this is for, and what they asked for.
String buildGoalsBlock(PlanBrief brief, {required String languageName}) {
  final b = StringBuffer()
    ..writeln('Draft a plan for this person.')
    ..writeln()
    ..writeln('Scope: ${brief.scope.label}')
    ..writeln('Training days per week: ${brief.daysPerWeek}')
    ..writeln('Time per session: about ${brief.sessionMinutes} minutes')
    ..writeln('Experience: ${brief.experience}');

  if (brief.goal != null) b.writeln('Goal: ${brief.goal}');
  if (brief.age != null) b.writeln('Age: ${brief.age!.round()}');
  if (brief.sex != null) b.writeln('Sex: ${brief.sex}');
  if (brief.equipment.isNotEmpty) {
    b.writeln('Equipment they train with: ${brief.equipment.join(', ')}');
  }
  if (brief.note != null && brief.note!.trim().isNotEmpty) {
    b
      ..writeln()
      ..writeln('What they said: ${brief.note!.trim()}');
  }

  b
    ..writeln()
    ..writeln('Write every routine "name", "note" and the "rationale" in $languageName.');
  return b.toString().trimRight();
}

/// Everything above, assembled into the request an adapter sends.
AiRequest planRequest({
  required PlanBrief brief,
  required List<Exercise> catalogue,
  required String languageName,
}) =>
    AiRequest(
      systemPrefix:
          '${planInstructions.trim()}\n\n<catalogue>\n${buildExerciseCatalogue(catalogue)}\n</catalogue>',
      systemTail: buildGoalsBlock(brief, languageName: languageName),
      userText: 'Draft the plan.',
      schema: planSchema,
      schemaName: 'workout_plan',
      // A full week is up to four routines of a dozen exercises, each a small object. Roomier
      // than the meal photo's ceiling because the answer genuinely is bigger, and a truncated
      // plan is worse than a slow one.
      answerTokens: 4000,
      // Off, and this is the considered choice rather than an omission — see the note at the top
      // of this file.
      cachePrefix: false,
    );
