import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_open_gym/data/ai/ai_key_store.dart';
import 'package:my_open_gym/data/ai/gemini_adapter.dart';
import 'package:my_open_gym/data/ai/openai_adapter.dart';
import 'package:my_open_gym/data/ai/vision_adapter.dart';
import 'package:my_open_gym/domain/ai/ai_provider.dart';

/// The Gemini and OpenAI adapters.
///
/// Both providers changed shape substantially during 2026 — Google moved from `generateContent`
/// with `contents`/`parts`/`inline_data` to `/v1beta/interactions` with a flat `input`, and OpenAI
/// from `/v1/chat/completions` to `/v1/responses` with `input_text`/`input_image` and
/// `text.format`. Code written from memory of either older API is wrong in several places at once
/// and fails only against the live service.
///
/// So these tests do something the Anthropic ones do not need to: they pin the *specific* fields
/// that differ from the superseded APIs, and assert the old spellings are absent. That turns a
/// silent 400 in a user's kitchen into a red test here.
void main() {
  const gemini = AiModel('gemini-3.7-flash', 'Gemini 3.7 Flash', (inPerM: 0.75, outPerM: 3.75));
  const openai = AiModel('gpt-5.6-terra', 'GPT-5.6 Terra', (inPerM: 2, outPerM: 12));
  const secret = 'THE-SECRET-KEY';

  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 7, 8, 9, 0xFF, 0xD9]);

  AiRequest req({String? hint}) => AiRequest(
        jpeg: jpeg,
        vocabulary: '# protein\nf0001 Chicken breast',
        customFoods: 'cf1 My shake',
        language: 'Spanish',
        hint: hint,
      );

  const goodAnswer = {
    'confidence': 'high',
    'items': [
      {'fid': 'f0001', 'name': 'Chicken breast', 'grams': 180}
    ],
  };

  group('Gemini request body', () {
    test('posts to the interactions endpoint with the Google key header', () async {
      late http.Request seen;
      final a = GeminiAdapter(
        model: gemini,
        keys: MemoryAiKeyStore(const {'google': secret}),
        client: _FakeClient((r) {
          seen = r;
          return http.Response(_geminiBody(goodAnswer), 200);
        }),
      );

      await a.readMeal(req());
      expect(seen.url.toString(),
          'https://generativelanguage.googleapis.com/v1beta/interactions');
      // Google takes the key in its own header, not an Authorization bearer.
      expect(seen.headers['x-goog-api-key'], secret);
      expect(seen.headers.containsKey('Authorization'), isFalse);
    });

    test('sends a flat image part, not the superseded inline_data nesting', () {
      final b = buildGeminiBody(req(), gemini);
      final input = b['input'] as List;
      final image = input.firstWhere((p) => (p as Map)['type'] == 'image') as Map;

      expect(image['mime_type'], 'image/jpeg');
      expect(base64Decode(image['data'] as String), jpeg);

      // The old generateContent spelling. Its absence is the point of the test.
      final rendered = jsonEncode(b);
      expect(rendered, isNot(contains('inline_data')));
      expect(rendered, isNot(contains('inlineData')));
      expect(b.containsKey('contents'), isFalse);
    });

    test('constrains the answer with response_format, not responseSchema', () {
      final b = buildGeminiBody(req(), gemini);
      final fmt = b['response_format'] as Map;
      expect(fmt['mime_type'], 'application/json');
      expect(fmt['schema'], isA<Map>());

      final rendered = jsonEncode(b);
      expect(rendered, isNot(contains('responseSchema')));
      expect(rendered, isNot(contains('responseMimeType')));
    });

    test('the catalogue goes in system_instruction and the volatile parts do not', () {
      final b = buildGeminiBody(req(hint: 'big portion'), gemini);
      final system = b['system_instruction'] as String;

      expect(system, contains('f0001 Chicken breast'));
      expect(system, isNot(contains('Spanish')));
      expect(system, isNot(contains('My shake')));
      expect(system, isNot(contains('big portion')));

      final text = (b['input'] as List)
          .firstWhere((p) => (p as Map)['type'] == 'text') as Map;
      expect(text['text'], contains('Spanish'));
      expect(text['text'], contains('big portion'));
    });

    test('the output ceiling leaves room for thinking tokens', () {
      // Gemini 3.7 Flash thinks, and thinking counts against this. A ceiling sized only for the
      // JSON gets eaten before the answer starts and truncates it.
      final cfg = buildGeminiBody(req(), gemini)['generation_config'] as Map;
      expect(cfg['max_output_tokens'], greaterThanOrEqualTo(4000));
    });
  });

  group('Gemini response', () {
    Future<AiResult> respond(String body, {int status = 200}) {
      final a = GeminiAdapter(
        model: gemini,
        keys: MemoryAiKeyStore(const {'google': secret}),
        client: _FakeClient((_) => http.Response(body, status)),
      );
      return a.readMeal(req());
    }

    test('finds the text inside the model_output step', () async {
      final r = await respond(_geminiBody(goodAnswer));
      expect(r, isA<AiDraft>());
      expect(((r as AiDraft).raw as Map)['items'], hasLength(1));
    });

    test('steps before the model_output one are skipped, not indexed past', () async {
      final withThought = jsonEncode({
        'steps': [
          {'type': 'thought', 'content': <Object>[]},
          {
            'type': 'model_output',
            'content': [
              {'type': 'text', 'text': jsonEncode(goodAnswer)}
            ],
          },
        ],
      });
      expect(await respond(withThought), isA<AiDraft>());
    });

    test('a shape it does not recognise never throws', () async {
      for (final junk in ['not json', '{}', '{"steps":"nope"}', '{"steps":[]}']) {
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

      await a.readMeal(req());
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
      return a.readMeal(req());
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
          final r = await build(status).readMeal(req());
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

      for (final a in <HttpVisionAdapter>[
        GeminiAdapter(model: gemini, keys: MemoryAiKeyStore(), client: client),
        OpenAiAdapter(model: openai, keys: MemoryAiKeyStore(), client: client),
      ]) {
        final r = await a.readMeal(req());
        expect((r as AiFailure).kind, AiFailureKind.notConfigured);
      }
      expect(called, isFalse);
    });

    test('the key never appears in a failure from either adapter', () async {
      for (final a in <HttpVisionAdapter>[
        GeminiAdapter(
            model: gemini,
            keys: MemoryAiKeyStore(const {'google': secret}),
            client: _FakeClient((_) => http.Response('{"error":"bad key $secret"}', 401))),
        OpenAiAdapter(
            model: openai,
            keys: MemoryAiKeyStore(const {'openai': secret}),
            client: _FakeClient((_) => http.Response('{"error":"bad key $secret"}', 401))),
      ]) {
        final r = await a.readMeal(req());
        expect(r.toString(), isNot(contains(secret)));
      }
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
      'steps': [
        {
          'type': 'model_output',
          'content': [
            {'type': 'text', 'text': jsonEncode(payload)}
          ],
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
