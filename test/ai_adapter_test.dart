import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:my_wellness/data/ai/ai_key_store.dart';
import 'package:my_wellness/data/ai/anthropic_adapter.dart';
import 'package:my_wellness/domain/ai/ai_provider.dart';
import 'package:my_wellness/domain/ai/meal_photo_prompt.dart';

/// The wire format, and the handling of everything that can come back down it.
///
/// No network and no mocking library: `http.Client` arrives through the constructor and the fake
/// below is twenty lines, which is the whole reason `package:http` is a dependency instead of
/// `dart:io`'s `HttpClient`.
void main() {
  const opus = AiModel('claude-opus-5', 'Claude Opus 5', (inPerM: 5, outPerM: 25));
  const haiku = AiModel('claude-haiku-4-5', 'Claude Haiku 4.5', (inPerM: 1, outPerM: 5),
      supportsEffort: false);

  const secret = 'sk-ant-api03-THE-SECRET';

  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 0xFF, 0xD9]);

  /// Built through the feature's own composer rather than by hand, so these tests pin the bytes
  /// the app actually sends — the adapter renders an envelope, but which half carries the
  /// catalogue and which carries the language is `meal_photo_prompt.dart`'s decision.
  AiRequest req({String? hint, String customFoods = '', String language = 'English'}) =>
      mealPhotoRequest(
        jpeg: jpeg,
        vocabulary: '# protein\nf0001 Chicken breast',
        customFoods: customFoods,
        languageName: language,
        hint: hint,
      );

  /// A canned answer in the shape the API actually returns one.
  String body(Object? payload, {String stopReason = 'end_turn', int? cached}) => jsonEncode({
        'stop_reason': stopReason,
        'content': [
          {'type': 'text', 'text': jsonEncode(payload)}
        ],
        if (cached != null) 'usage': {'cache_read_input_tokens': cached},
      });

  const goodAnswer = {
    'confidence': 'high',
    'items': [
      {'fid': 'f0001', 'name': 'Chicken breast', 'grams': 180}
    ],
  };

  group('the request body', () {
    test('carries the image as base64 jpeg, and the schema', () {
      final b = buildBody(req(), opus);

      final content = ((b['messages'] as List).single as Map)['content'] as List;
      final image = content.first as Map;
      expect(image['type'], 'image');
      final source = image['source'] as Map;
      expect(source['type'], 'base64');
      expect(source['media_type'], 'image/jpeg');
      expect(base64Decode(source['data'] as String), jpeg);

      final format = (b['output_config'] as Map)['format'] as Map;
      expect(format['type'], 'json_schema');
      expect(format['schema'], isA<Map>());
    });

    test('sends neither thinking nor a prefill, both of which are a 400', () {
      final b = buildBody(req(), opus);
      expect(b.containsKey('thinking'), isFalse);
      expect(b.containsKey('budget_tokens'), isFalse);
      // Every message must be from the user; a trailing assistant turn is a prefill.
      for (final m in b['messages'] as List) {
        expect((m as Map)['role'], 'user');
      }
    });

    test('effort is sent only to a model that accepts it', () {
      // Haiku 4.5 predates the parameter and rejects the request outright, so sending it blindly
      // would make the cheapest option in the picker the one that never works.
      expect((buildBody(req(), opus)['output_config'] as Map).containsKey('effort'), isTrue);
      expect((buildBody(req(), haiku)['output_config'] as Map).containsKey('effort'), isFalse);
    });

    test('the cache breakpoint sits on the stable block, and nothing volatile is above it', () {
      final system = buildBody(
        req(language: 'Spanish', customFoods: 'cf1 My shake', hint: 'big portion'),
        opus,
      )['system'] as List;

      expect(system, hasLength(2));
      final cached = system.first as Map;
      final tail = system.last as Map;

      expect(cached['cache_control'], {'type': 'ephemeral'});
      expect(tail.containsKey('cache_control'), isFalse);

      // Everything that differs between two requests must be below the breakpoint, or the prefix
      // stops matching and the cache silently never hits.
      final prefix = cached['text'] as String;
      expect(prefix, contains('f0001 Chicken breast'));
      expect(prefix, isNot(contains('Spanish')));
      expect(prefix, isNot(contains('My shake')));
      expect(prefix, isNot(contains('big portion')));

      final volatile = tail['text'] as String;
      expect(volatile, contains('Spanish'));
      expect(volatile, contains('My shake'));
      expect(volatile, contains('big portion'));
    });

    test('the cached prefix is byte-identical across two different requests', () {
      final a = (buildBody(req(hint: 'one'), opus)['system'] as List).first as Map;
      final b = (buildBody(req(hint: 'two'), opus)['system'] as List).first as Map;
      expect(a['text'], b['text']);
    });
  });

  group('headers and the key', () {
    test('the key goes in x-api-key and the version is pinned', () async {
      late http.Request seen;
      final a = AnthropicAdapter(
        model: opus,
        keys: MemoryAiKeyStore(const {'anthropic': secret}),
        client: _FakeClient((r) {
          seen = r;
          return http.Response(body(goodAnswer), 200);
        }),
      );

      await a.run(req());
      expect(seen.headers['x-api-key'], secret);
      expect(seen.headers['anthropic-version'], '2023-06-01');
      expect(seen.url.toString(), 'https://api.anthropic.com/v1/messages');
    });

    test('with no key stored, nothing is sent at all', () async {
      var called = false;
      final a = AnthropicAdapter(
        model: opus,
        keys: MemoryAiKeyStore(),
        client: _FakeClient((_) {
          called = true;
          return http.Response(body(goodAnswer), 200);
        }),
      );

      final r = await a.run(req());
      expect(r, isA<AiFailure>());
      expect((r as AiFailure).kind, AiFailureKind.notConfigured);
      expect(called, isFalse, reason: 'a request with no key is a wasted round trip');
    });

    test('the key never appears in any failure the adapter produces', () async {
      // The adapter is the only place the key exists in memory. Every path out of it — including
      // the one that catches an exception nobody anticipated — has to be checked.
      for (final outcome in <Object Function()>[
        () => throw const SocketException('no route'),
        () => throw TimeoutException('slow'),
        () => http.Response('{"error":{"message":"bad key $secret"}}', 401),
        () => http.Response('{"error":"rate limited $secret"}', 429),
        () => http.Response('not json at all $secret', 200),
        () => throw StateError('unexpected $secret'),
      ]) {
        final a = AnthropicAdapter(
          model: opus,
          keys: MemoryAiKeyStore(const {'anthropic': secret}),
          client: _FakeClient((_) => outcome() as http.Response),
        );

        final r = await a.run(req());
        expect(r, isA<AiFailure>());
        // Note what this does and does not prove. It proves no path out of the adapter renders
        // the key, including the bare catch. It does not prove a future field could not carry it
        // without reaching toString — the guarantee there is that AiFailure holds only a kind,
        // which is a design to keep rather than a thing this test can check.
        expect(r.toString(), isNot(contains(secret)));
        expect(r.toString(), isNot(contains('sk-ant')));
      }
    });
  });

  group('reading the answer', () {
    Future<AiResult> respond(Object Function() f) {
      final a = AnthropicAdapter(
        model: opus,
        keys: MemoryAiKeyStore(const {'anthropic': secret}),
        client: _FakeClient((_) => f() as http.Response),
      );
      return a.run(req());
    }

    Future<AiFailureKind> kindOf(Object Function() f) async =>
        ((await respond(f)) as AiFailure).kind;

    test('a good answer comes back raw and unvalidated', () async {
      final r = await respond(() => http.Response(body(goodAnswer, cached: 1024), 200));
      expect(r, isA<AiDraft>());
      final d = r as AiDraft;
      expect((d.raw as Map)['items'], hasLength(1));
      // The cache figure is the only way to tell whether the prefix is being reused at all.
      expect(d.cachedTokens, 1024);
    });

    test('a text block behind thinking blocks is still found', () async {
      final withThinking = jsonEncode({
        'stop_reason': 'end_turn',
        'content': [
          {'type': 'thinking', 'thinking': ''},
          {'type': 'text', 'text': jsonEncode(goodAnswer)},
        ],
      });
      expect(await respond(() => http.Response(withThinking, 200)), isA<AiDraft>());
    });

    test('a refusal is its own outcome, not an unreadable answer', () async {
      // It arrives as a perfectly ordinary 200, so stop_reason has to be checked before content.
      expect(
        await kindOf(() => http.Response(body(goodAnswer, stopReason: 'refusal'), 200)),
        AiFailureKind.refused,
      );
    });

    test('status codes map to something the sheet can act on', () async {
      expect(await kindOf(() => http.Response('{}', 401)), AiFailureKind.badKey);
      expect(await kindOf(() => http.Response('{}', 403)), AiFailureKind.badKey);
      expect(await kindOf(() => http.Response('{}', 429)), AiFailureKind.rateLimited);
      expect(await kindOf(() => http.Response('{}', 500)), AiFailureKind.providerDown);
      expect(await kindOf(() => http.Response('{}', 503)), AiFailureKind.providerDown);
      // The rest of the 4xx range is the request being turned down rather than the key — a model
      // id the provider has retired lands here, and reading as "unreadable" would send the user
      // looking at their photograph for a fault that is in the app.
      expect(await kindOf(() => http.Response('{}', 400)), AiFailureKind.rejected);
      expect(await kindOf(() => http.Response('{}', 404)), AiFailureKind.rejected);
      expect(await kindOf(() => http.Response('{}', 418)), AiFailureKind.rejected);
      // ...and 3xx, which no provider sends, is still not any of those.
      expect(await kindOf(() => http.Response('{}', 302)), AiFailureKind.unreadable);
    });

    group('the two 429s are told apart', () {
      /// The body OpenAI sends when the key is perfectly good and the balance is zero. Both
      /// fields carry the marker, and each is checked on its own below because providers have
      /// been inconsistent about which one they populate.
      String quota({String? code, String? type}) => jsonEncode({
            'error': {
              'message': 'You exceeded your current quota, please check your plan and billing '
                  'details.',
              'type': type,
              'param': null,
              'code': code,
            },
          });

      test('an exhausted balance is not a rate limit', () async {
        // The bug this exists for: a new key with no credit was told to "try again in a minute",
        // which is advice that can never come true. Nothing here fixes itself by waiting.
        expect(
          await kindOf(() => http.Response(quota(code: 'insufficient_quota'), 429)),
          AiFailureKind.noCredit,
        );
        expect(
          await kindOf(() => http.Response(quota(type: 'insufficient_quota'), 429)),
          AiFailureKind.noCredit,
        );
        expect(
          await kindOf(() => http.Response(quota(code: 'billing_hard_limit_reached'), 429)),
          AiFailureKind.noCredit,
        );
      });

      test('a real rate limit still reads as one', () async {
        // The discriminator has to be the code, not the status and not the prose — a 429 that is
        // genuinely about speed must keep the advice that works for it.
        expect(
          await kindOf(() => http.Response(quota(code: 'rate_limit_exceeded'), 429)),
          AiFailureKind.rateLimited,
        );
        // And an unclassifiable 429 stays what the status code alone says, rather than guessing.
        for (final body in ['', 'not json', '{}', '{"error":"insufficient_quota"}', '[]']) {
          expect(await kindOf(() => http.Response(body, 429)), AiFailureKind.rateLimited,
              reason: body);
        }
      });

      test('the marker only ever refines a 429', () async {
        // A 401 carrying the word is still a refused key: the body decides between two readings
        // of one status code, it does not overrule the status code.
        expect(
          await kindOf(() => http.Response(quota(code: 'insufficient_quota'), 401)),
          AiFailureKind.badKey,
        );
        expect(
          await kindOf(() => http.Response(quota(code: 'insufficient_quota'), 400)),
          AiFailureKind.rejected,
        );
      });
    });

    test('network trouble reads as offline, and a slow reply as a timeout', () async {
      expect(
        await kindOf(() => throw const SocketException('no route to host')),
        AiFailureKind.offline,
      );
      expect(
        await kindOf(() => throw http.ClientException('connection closed')),
        AiFailureKind.offline,
      );
      expect(await kindOf(() => throw TimeoutException('slow')), AiFailureKind.timeout);
    });

    test('a malformed 200 never throws', () async {
      expect(await kindOf(() => http.Response('not json', 200)), AiFailureKind.unreadable);
      expect(await kindOf(() => http.Response('[]', 200)), AiFailureKind.unreadable);
      expect(await kindOf(() => http.Response('{"content":"nope"}', 200)),
          AiFailureKind.unreadable);
      expect(await kindOf(() => http.Response('{"content":[]}', 200)), AiFailureKind.unreadable);
      // A text block whose contents are not the agreed JSON.
      expect(
        await kindOf(() => http.Response(
            jsonEncode({
              'content': [
                {'type': 'text', 'text': 'I had trouble with that.'}
              ]
            }),
            200)),
        AiFailureKind.unreadable,
      );
    });
  });

  group('the connection test', () {
    Future<AiFailureKind?> probe(
      Object Function() f, {
      Map<String, String>? keys,
      void Function(http.Request)? watch,
    }) {
      final a = AnthropicAdapter(
        model: opus,
        keys: MemoryAiKeyStore(keys ?? const {'anthropic': secret}),
        client: _FakeClient((r) {
          watch?.call(r);
          return f() as http.Response;
        }),
      );
      return a.probe();
    }

    test('goes to the real endpoint, with the real body and the chosen model', () async {
      // The whole value of testing this way rather than with a free list-models call: a model id
      // the provider has retired, or a request shape it has moved past, fails here exactly as it
      // would fail on a real photo. A probe that sent something else would pass and prove nothing.
      late http.Request seen;
      await probe(() => http.Response('{}', 200), watch: (r) => seen = r);

      expect(seen.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(seen.headers['x-api-key'], secret);
      final sent = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(sent['model'], opus.id);
      expect((sent['output_config'] as Map)['format'], isA<Map>());
    });

    test('carries a real jpeg, and none of what makes a meal read expensive', () async {
      late http.Request seen;
      await probe(() => http.Response('{}', 200), watch: (r) => seen = r);

      final sent = jsonDecode(seen.body) as Map<String, dynamic>;
      final content = (sent['messages'] as List).single as Map;
      final image = (content['content'] as List).first as Map;
      final bytes = base64Decode(((image['source']) as Map)['data'] as String);
      // SOI and EOI — a decodable image rather than a handful of bytes a provider would reject.
      expect(bytes.sublist(0, 2), [0xFF, 0xD8]);
      expect(bytes.sublist(bytes.length - 2), [0xFF, 0xD9]);
      // A real plate is ~100–180 KB and about a thousand image tokens; this is a rounding error.
      expect(bytes.length, lessThan(1024));

      // A catalogue is the expensive half of a real request, and the probe carries none at all.
      // That, and the image above, are what make a test cost a fraction of what a real call does
      // — which is the claim the settings screen prints next to the button. Asserted as a size
      // rather than by naming any one feature's block, because the probe is shared by all of
      // them: whatever gets added here later still has to stay this small.
      final prompt = [
        for (final block in sent['system'] as List) (block as Map)['text'] as String,
      ].join();
      expect(prompt.length, lessThan(400));
      expect(prompt, isNot(contains('Chicken breast')));
      // Small answer too — a probe that let a model write for 1,500 tokens would cost more than
      // the request it is testing.
      expect(sent['max_tokens'], lessThan(100));
    });

    test('null means it worked, and the answer is never read', () async {
      // A 200 is the whole verdict. Whatever the model said about a 64-pixel grey square is not
      // something a connection test has an opinion about.
      expect(await probe(() => http.Response('{}', 200)), isNull);
      expect(await probe(() => http.Response('not json at all', 200)), isNull);
    });

    test('every way it can fail comes back as something the screen can say', () async {
      expect(await probe(() => http.Response('{}', 401)), AiFailureKind.badKey);
      expect(await probe(() => http.Response('{}', 404)), AiFailureKind.rejected);
      expect(await probe(() => http.Response('{}', 429)), AiFailureKind.rateLimited);
      // The Test button is where an empty balance is actually met, so the refinement has to
      // survive this path too — probe judges on the status code, and this is the one case where
      // the status code is not the whole story.
      expect(
        await probe(() =>
            http.Response('{"error":{"code":"insufficient_quota"}}', 429)),
        AiFailureKind.noCredit,
      );
      expect(await probe(() => http.Response('{}', 500)), AiFailureKind.providerDown);
      expect(await probe(() => throw const SocketException('no route')), AiFailureKind.offline);
      expect(await probe(() => throw TimeoutException('slow')), AiFailureKind.timeout);
    });

    test('with no key stored, nothing is sent at all', () async {
      var called = false;
      final kind = await probe(
        () => http.Response('{}', 200),
        keys: const {},
        watch: (_) => called = true,
      );
      expect(kind, AiFailureKind.notConfigured);
      expect(called, isFalse);
    });

    test('the key never appears in what the probe hands back', () async {
      for (final outcome in <Object Function()>[
        () => http.Response('{"error":{"message":"bad key $secret"}}', 401),
        () => throw StateError('unexpected $secret'),
      ]) {
        final kind = await probe(() => outcome() as http.Response);
        expect(kind.toString(), isNot(contains(secret)));
        expect(kind.toString(), isNot(contains('sk-ant')));
      }
    });
  });
}

/// Twenty lines instead of a mocking package, matching the repo's constructor-injection habit.
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
