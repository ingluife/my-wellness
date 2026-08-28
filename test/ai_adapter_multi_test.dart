import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_open_gym/data/ai/ai_key_store.dart';
import 'package:my_open_gym/data/ai/gemini_adapter.dart';
import 'package:my_open_gym/data/ai/openai_adapter.dart';
import 'package:my_open_gym/data/ai/ai_adapter.dart';
import 'package:my_open_gym/domain/ai/ai_provider.dart';
import 'package:my_open_gym/domain/ai/meal_photo_prompt.dart';

/// The Gemini and OpenAI adapters.
///
/// OpenAI changed shape substantially during 2026 — `/v1/chat/completions` to `/v1/responses`
/// with `input_text`/`input_image` and `text.format` — and code written from memory of the older
/// API is wrong in several places at once, failing only against the live service. So these tests
/// do something the Anthropic ones do not need to: they pin the *specific* fields that differ
/// from the superseded API, and assert the old spellings are absent.
///
/// Google's half is pinned for the opposite reason. The adapter briefly targeted
/// `/v1beta/interactions`, Google's newer unified endpoint, and had to be moved back to
/// `generateContent` on evidence: a key working elsewhere got a flat 429 from `interactions` on
/// every request with the account nowhere near its quota, and a raw POST to that endpoint
/// uploaded its body and then returned zero bytes until it timed out. So the assertions here
/// hold the `generateContent` spellings — `contents`/`parts`/`inline_data`, `system_instruction`
/// as an object, `generationConfig.responseSchema` — and it is `interactions`' flat `input`
/// whose absence is now the thing worth checking. See gemini_adapter.dart's own note.
void main() {
  const gemini = AiModel('gemini-3.7-flash', 'Gemini 3.7 Flash', (inPerM: 0.75, outPerM: 3.75));
  const openai = AiModel('gpt-5.6-terra', 'GPT-5.6 Terra', (inPerM: 2, outPerM: 12));
  const secret = 'THE-SECRET-KEY';

  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 7, 8, 9, 0xFF, 0xD9]);

  AiRequest req({String? hint}) => mealPhotoRequest(
        jpeg: jpeg,
        vocabulary: '# protein\nf0001 Chicken breast',
        customFoods: 'cf1 My shake',
        languageName: 'Spanish',
        hint: hint,
      );

  /// A text-only request, which is what every feature other than the meal photo sends. Neither
  /// provider may grow an empty image part for one.
  AiRequest textReq() => const AiRequest(
        systemPrefix: 'You draft things.',
        systemTail: 'Answer in Spanish.',
        userText: 'Draft it.',
        schema: {
          'type': 'object',
          'properties': {
            'ok': {'type': 'boolean'},
          },
          'required': ['ok'],
        },
        schemaName: 'draft',
        answerTokens: 900,
      );

  const goodAnswer = {
    'confidence': 'high',
    'items': [
      {'fid': 'f0001', 'name': 'Chicken breast', 'grams': 180}
    ],
  };

  group('Gemini request body', () {
    /// The parts of the single user turn.
    List<Object?> partsOf(Map<String, dynamic> b) =>
        ((b['contents'] as List).single as Map)['parts'] as List;

    test('posts to generateContent, with the model in the path and the key in its header',
        () async {
      late http.Request seen;
      final a = GeminiAdapter(
        model: gemini,
        keys: MemoryAiKeyStore(const {'google': secret}),
        client: _FakeClient((r) {
          seen = r;
          return http.Response(_geminiBody(goodAnswer), 200);
        }),
      );

      await a.run(req());
      // The model id is in the URL here, not the body — the one structural difference from the
      // other two adapters, and easy to lose in a refactor that treats endpoints as constants.
      expect(
        seen.url.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-3.7-flash:generateContent',
      );
      // Google takes the key in its own header, not an Authorization bearer.
      expect(seen.headers['x-goog-api-key'], secret);
      expect(seen.headers.containsKey('Authorization'), isFalse);
      // Never the endpoint that answered every request with a 429 and then with nothing at all.
      expect(seen.url.path, isNot(contains('interactions')));
    });

    test('nests the image as inline_data with a mime type', () {
      final b = buildGeminiBody(req(), gemini);
      final image = partsOf(b).firstWhere((p) => (p as Map).containsKey('inline_data')) as Map;
      final data = image['inline_data'] as Map;

      expect(data['mime_type'], 'image/jpeg');
      expect(base64Decode(data['data'] as String), jpeg);

      // Not the interactions shape: flat typed parts in a top-level `input`.
      expect(b.containsKey('input'), isFalse);
      expect(jsonEncode(b), isNot(contains('"type":"image"')));
    });

    test('constrains the answer with responseSchema inside generationConfig', () {
      final b = buildGeminiBody(req(), gemini);
      final cfg = b['generationConfig'] as Map;

      expect(cfg['responseMimeType'], 'application/json');
      expect(cfg['responseSchema'], isA<Map>());
      // response_format is the interactions spelling and is not a field here.
      expect(b.containsKey('response_format'), isFalse);
    });

    test('the schema is sent in Google dialect, not as JSON Schema', () {
      // `responseSchema` is the OpenAPI-derived Schema message, whose type names are upper case.
      // Sending the lower-case JSON Schema spelling the other two providers take is a 400 from
      // every model at once — which surfaces as "the model may no longer exist" and sends the
      // next reader hunting through the model table for a fault that is in the schema.
      final rendered = jsonEncode(buildGeminiBody(req(), gemini)['generationConfig']);

      expect(rendered, isNot(contains('"type":"object"')));
      expect(rendered, isNot(contains('"type":"string"')));
      expect(rendered, isNot(contains('"type":"array"')));
      expect(rendered, contains('"type":"OBJECT"'));
      expect(rendered, contains('"type":"ARRAY"'));

      // A keyword the Schema message has no field for; an unknown field is the other 400.
      expect(rendered, isNot(contains('additionalProperties')));

      // ...and the shared schema itself is untouched, because Anthropic and OpenAI send it as it
      // stands. A conversion that mutated the original would break them both silently.
      expect(mealPhotoSchema['type'], 'object');
      expect(mealPhotoSchema['additionalProperties'], isFalse);
    });

    test('the conversion reaches every level and leaves enum values alone', () {
      final converted = geminiSchema(mealPhotoSchema) as Map;
      final props = converted['properties'] as Map;

      // Nested: items -> items -> properties -> per100.
      final item = (props['items'] as Map)['items'] as Map;
      expect(item['type'], 'OBJECT');
      final per100 = (item['properties'] as Map)['per100'] as Map;
      expect(per100['type'], 'OBJECT');
      expect((per100['properties'] as Map)['kcal']['type'], 'NUMBER');

      // `enum` carries data, not types. Upper-casing 'high' would change what the model may say.
      expect((props['confidence'] as Map)['enum'], ['high', 'medium', 'low']);
    });

    test('the catalogue goes in system_instruction and the volatile parts do not', () {
      final b = buildGeminiBody(req(hint: 'big portion'), gemini);
      // An object with parts, not a bare string: the REST shape differs from the SDKs', which
      // take a string and wrap it for you.
      final system =
          ((b['system_instruction'] as Map)['parts'] as List).single as Map;
      final prefix = system['text'] as String;

      expect(prefix, contains('f0001 Chicken breast'));
      expect(prefix, isNot(contains('Spanish')));
      expect(prefix, isNot(contains('My shake')));
      expect(prefix, isNot(contains('big portion')));

      final text = partsOf(b).firstWhere((p) => (p as Map).containsKey('text')) as Map;
      expect(text['text'], contains('Spanish'));
      expect(text['text'], contains('big portion'));
    });

    test('the output ceiling leaves room for thinking tokens', () {
      // Gemini 3.7 Flash thinks, and thinking counts against this. A ceiling sized only for the
      // JSON gets eaten before the answer starts and truncates it.
      final cfg = buildGeminiBody(req(), gemini)['generationConfig'] as Map;
      expect(cfg['maxOutputTokens'], greaterThanOrEqualTo(4000));
    });
  });

  group('Gemini response', () {
    Future<AiResult> respond(String body, {int status = 200}) {
      final a = GeminiAdapter(
        model: gemini,
        keys: MemoryAiKeyStore(const {'google': secret}),
        client: _FakeClient((_) => http.Response(body, status)),
      );
      return a.run(req());
    }

    test('finds the text in the first candidate', () async {
      final r = await respond(_geminiBody(goodAnswer));
      expect(r, isA<AiDraft>());
      expect(((r as AiDraft).raw as Map)['items'], hasLength(1));
    });

    test('a thinking part ahead of the answer is skipped, not indexed past', () async {
      final withThought = jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'thought': true, 'text': 'weighing the rice'},
                {'text': jsonEncode(goodAnswer)},
              ],
            },
          },
        ],
      });
      expect(await respond(withThought), isA<AiDraft>());
    });

    test('a blocked prompt is a refusal, not an unreadable answer', () async {
      // It arrives as an ordinary 200 with no candidates at all, so promptFeedback has to be
      // read before reaching for them. Telling the user the answer was unreadable would send
      // them round a retry loop over something retrying cannot fix.
      final blocked = jsonEncode({
        'promptFeedback': {'blockReason': 'SAFETY'},
      });
      expect(((await respond(blocked)) as AiFailure).kind, AiFailureKind.refused);

      final stopped = jsonEncode({
        'candidates': [
          {'finishReason': 'SAFETY', 'content': <String, Object>{}},
        ],
      });
      expect(((await respond(stopped)) as AiFailure).kind, AiFailureKind.refused);
    });

    test('a shape it does not recognise never throws', () async {
      for (final junk in [
        'not json',
        '{}',
        '{"candidates":"nope"}',
        '{"candidates":[]}',
        '{"candidates":[{"content":{"parts":[]}}]}',
        // Every part is reasoning and none is the answer.
        '{"candidates":[{"content":{"parts":[{"thought":true,"text":"hm"}]}}]}',
      ]) {
        final r = await respond(junk);
        expect((r as AiFailure).kind, AiFailureKind.unreadable, reason: junk);
      }
    });
  });

  group('OpenAI request body', () {
    test('posts to /v1/responses with a bearer token', () async {
      late http.Request seen;
      final a = OpenAiAdapter(
        model: openai,
        keys: MemoryAiKeyStore(const {'openai': secret}),
        client: _FakeClient((r) {
          seen = r;
          return http.Response(_openAiBody(goodAnswer), 200);
        }),
      );

      await a.run(req());
      expect(seen.url.toString(), 'https://api.openai.com/v1/responses');
      expect(seen.headers['Authorization'], 'Bearer $secret');
      // Not chat completions. The whole body shape below depends on this being right.
      expect(seen.url.path, isNot(contains('chat')));
    });

    test('uses the Responses content types, not the chat-completions ones', () {
      final b = buildOpenAiBody(req(), openai);
      final user = (b['input'] as List).last as Map;
      final content = user['content'] as List;

      final image = content.firstWhere((p) => (p as Map)['type'] == 'input_image') as Map;
      final text = content.firstWhere((p) => (p as Map)['type'] == 'input_text') as Map;

      // A data URL inline, not a {url: ...} object.
      expect(image['image_url'], startsWith('data:image/jpeg;base64,'));
      expect(base64Decode((image['image_url'] as String).split(',').last), jpeg);
      expect(text['text'], contains('Spanish'));

      // `messages` and the bare `text`/`image_url` part types belong to the superseded API.
      expect(b.containsKey('messages'), isFalse);
      for (final p in content) {
        expect((p as Map)['type'], anyOf('input_image', 'input_text'));
      }
    });

    test('the schema hangs off text.format with strict set', () {
      final b = buildOpenAiBody(req(), openai);
      final fmt = (b['text'] as Map)['format'] as Map;

      expect(fmt['type'], 'json_schema');
      expect(fmt['strict'], isTrue);
      expect(fmt['name'], isNotEmpty);
      expect(fmt['schema'], isA<Map>());

      // Top-level response_format is the chat-completions spelling and is silently ignored here.
      expect(b.containsKey('response_format'), isFalse);
    });

    test('instructions go in a developer-role turn ahead of the user turn', () {
      final input = buildOpenAiBody(req(), openai)['input'] as List;
      expect((input.first as Map)['role'], 'developer');
      expect((input.first as Map)['content'], contains('f0001 Chicken breast'));
      expect((input.last as Map)['role'], 'user');
    });

    test('the output ceiling leaves room for reasoning tokens', () {
      final b = buildOpenAiBody(req(), openai);
      expect(b['max_output_tokens'], greaterThanOrEqualTo(4000));
      // The chat-completions name for it, which the Responses API does not accept.
      expect(b.containsKey('max_tokens'), isFalse);
    });
  });

  group('OpenAI response', () {
    Future<AiResult> respond(String body, {int status = 200}) {
      final a = OpenAiAdapter(
        model: openai,
        keys: MemoryAiKeyStore(const {'openai': secret}),
        client: _FakeClient((_) => http.Response(body, status)),
      );
      return a.run(req());
    }

    test('finds the output_text part', () async {
      final r = await respond(_openAiBody(goodAnswer));
      expect(r, isA<AiDraft>());
      expect(((r as AiDraft).raw as Map)['items'], hasLength(1));
    });

    test('a reasoning item ahead of the message is stepped past', () async {
      final withReasoning = jsonEncode({
        'output': [
          {'type': 'reasoning', 'summary': <Object>[]},
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': jsonEncode(goodAnswer)}
            ],
          },
        ],
      });
      expect(await respond(withReasoning), isA<AiDraft>());
    });

    test('a shape it does not recognise never throws', () async {
      for (final junk in ['not json', '{}', '{"output":"nope"}', '{"output":[]}']) {
        final r = await respond(junk);
        expect((r as AiFailure).kind, AiFailureKind.unreadable, reason: junk);
      }
    });
  });

  group('shared handling holds for every provider', () {
    test('status codes map the same way whichever provider returned them', () async {
      for (final build in [
        (int s) => GeminiAdapter(
            model: gemini,
            keys: MemoryAiKeyStore(const {'google': secret}),
            client: _FakeClient((_) => http.Response('{}', s))),
        (int s) => OpenAiAdapter(
            model: openai,
            keys: MemoryAiKeyStore(const {'openai': secret}),
            client: _FakeClient((_) => http.Response('{}', s))),
      ]) {
        for (final (status, kind) in const [
          (401, AiFailureKind.badKey),
          (429, AiFailureKind.rateLimited),
          (503, AiFailureKind.providerDown),
        ]) {
          final r = await build(status).run(req());
          expect((r as AiFailure).kind, kind);
        }
      }
    });

    test('with no key stored, neither adapter sends anything', () async {
      var called = false;
      final client = _FakeClient((_) {
        called = true;
        return http.Response('{}', 200);
      });

      for (final a in <HttpAiAdapter>[
        GeminiAdapter(model: gemini, keys: MemoryAiKeyStore(), client: client),
        OpenAiAdapter(model: openai, keys: MemoryAiKeyStore(), client: client),
      ]) {
        final r = await a.run(req());
        expect((r as AiFailure).kind, AiFailureKind.notConfigured);
      }
      expect(called, isFalse);
    });

    test('the key never appears in a failure from either adapter', () async {
      for (final a in <HttpAiAdapter>[
        GeminiAdapter(
            model: gemini,
            keys: MemoryAiKeyStore(const {'google': secret}),
            client: _FakeClient((_) => http.Response('{"error":"bad key $secret"}', 401))),
        OpenAiAdapter(
            model: openai,
            keys: MemoryAiKeyStore(const {'openai': secret}),
            client: _FakeClient((_) => http.Response('{"error":"bad key $secret"}', 401))),
      ]) {
        final r = await a.run(req());
        expect(r.toString(), isNot(contains(secret)));
      }
    });

    // The envelope carries an optional image so features that are not about photographs can use
    // the same three adapters. What that must not do is leave a hole where the image was: an
    // empty image part is a 400 from both of these, and it would only ever be hit by the feature
    // that has no photo to send.
    test('a text-only request grows no empty image part', () {
      final g = buildGeminiBody(textReq(), gemini);
      final gParts = ((g['contents'] as List).single as Map)['parts'] as List;
      expect(gParts, hasLength(1));
      expect((gParts.single as Map).containsKey('inline_data'), isFalse);
      expect(gParts.single, contains('text'));

      final o = buildOpenAiBody(textReq(), openai);
      final oUser = (o['input'] as List).last as Map;
      final oParts = oUser['content'] as List;
      expect(oParts, hasLength(1));
      expect((oParts.single as Map)['type'], 'input_text');
    });

    test('the answer budget is the feature\'s, plus each provider\'s reasoning headroom', () {
      // Thinking tokens are charged against the same ceiling as the answer on both of these, so
      // a feature that asks for 900 tokens of JSON and gets a 900 ceiling gets truncated JSON.
      expect(buildGeminiBody(textReq(), gemini)['generationConfig'],
          containsPair('maxOutputTokens', 900 + GeminiAdapter.reasoningHeadroom));
      expect(buildOpenAiBody(textReq(), openai)['max_output_tokens'],
          900 + OpenAiAdapter.reasoningHeadroom);
    });
  });

  test('every model in the table has a plausible id and a real price', () {
    // Not a spell-check — a guard against the table being extended by pattern. An id invented to
    // look like its neighbours is a 404 the user reads as "this app is broken".
    for (final entry in aiModels.entries) {
      expect(aiProviders, contains(entry.key));
      expect(entry.value, isNotEmpty, reason: entry.key);
      for (final m in entry.value) {
        expect(m.id.trim(), m.id, reason: m.id);
        expect(m.id, isNotEmpty);
        expect(m.label, isNotEmpty);
        expect(m.price.inPerM, greaterThan(0), reason: m.id);
        expect(m.price.outPerM, greaterThan(m.price.inPerM), reason: m.id);
        expect(m.perPhoto, greaterThan(0));
        expect(m.perPhoto, lessThan(1), reason: 'a dollar a photo would be a bug, not a price');
      }
    }
  });

  test('no Google model is one a free-tier key cannot use', () {
    // The bug this pins: Google's table led with gemini-3.1-pro-preview, which its own pricing
    // page marks "Free Tier: Not available" — an API key with no billing account gets zero quota
    // for it and Google reports that as a plain 429. First in the table is also what a user gets
    // if they never open the Model picker, so every free-tier key was silently pointed at the one
    // model it could not use and told "too many requests" for a limit it never approached.
    //
    // It was dropped rather than demoted, so this checks the whole table and not just its head:
    // a Pro model anywhere in the picker is one a free-tier user can select and be refused by,
    // with no way to tell that apart from a real rate limit. Anthropic and OpenAI are not checked
    // because neither gates a model behind a billing tier this way.
    //
    // Matched on the id prefix rather than an exact list, because the trap is a *family*: the
    // next Pro id will not be spelled like this one, and an exact list would silently pass it.
    for (final m in aiModels['google']!) {
      expect(m.id, isNot(contains('-pro')),
          reason: '${m.id} is Pro — check the Free Tier column on the pricing page');
    }

    // ...and the default really is the first entry, which is what makes ordering load-bearing.
    expect(defaultModelFor('google')!.id, aiModels['google']!.first.id);
    expect(modelFor('google', null)!.id, aiModels['google']!.first.id);
  });

  test('every provider the settings screen offers has an adapter behind it', () {
    // The settings screen lists aiProviders. A provider with no model table is a row the user can
    // pick and then find broken.
    for (final p in aiProviders) {
      expect(aiModels[p], isNotNull, reason: '$p has no models');
      expect(defaultModelFor(p), isNotNull, reason: '$p has no default model');
    }
  });
}

String _geminiBody(Object payload) => jsonEncode({
      'candidates': [
        {
          'finishReason': 'STOP',
          'content': {
            'role': 'model',
            'parts': [
              {'text': jsonEncode(payload)}
            ],
          },
        },
      ],
    });

String _openAiBody(Object payload) => jsonEncode({
      'output': [
        {
          'type': 'message',
          'content': [
            {'type': 'output_text', 'text': jsonEncode(payload)}
          ],
        },
      ],
    });

class _FakeClient extends http.BaseClient {
  _FakeClient(this.respond);

  final http.Response Function(http.Request) respond;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final r = respond(request as http.Request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(r.body)),
      r.statusCode,
      request: request,
      headers: r.headers,
    );
  }
}
