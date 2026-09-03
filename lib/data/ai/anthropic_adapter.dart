import 'dart:convert';

import '../../domain/ai/ai_provider.dart';
import 'ai_adapter.dart';

/// Anthropic's Messages API.
///
/// Raw HTTP because there is no official Anthropic SDK for Dart. Everything about *handling* the
/// call — timeout, failure mapping, the rules about the key — is in [HttpAiAdapter]; this file
/// is only the shape of the request and where the answer sits in the reply.
class AnthropicAdapter extends HttpAiAdapter {
  AnthropicAdapter({required super.model, required super.keys, super.client});

  /// Pinned, not "latest". The wire format is a contract, and a silent change to it is exactly the
  /// breakage that shows up as "the feature stopped working" with nothing in the logs.
  static const apiVersion = '2023-06-01';

  @override
  String get providerId => 'anthropic';

  @override
  Uri get endpoint => Uri.parse('https://api.anthropic.com/v1/messages');

  @override
  Map<String, String> headers(String key) => {
        'content-type': 'application/json',
        'x-api-key': key,
        'anthropic-version': apiVersion,
      };

  @override
  Map<String, dynamic> body(AiRequest request) => buildBody(request, model);

  @override
  AiResult parse(Map<String, dynamic> decoded) {
    // A refusal arrives as a perfectly ordinary 200. Checking stop_reason before reading content
    // is the only way to tell it apart from an answer.
    if (decoded['stop_reason'] == 'refusal') {
      return const AiFailure(AiFailureKind.refused);
    }

    final content = decoded['content'];
    if (content is! List) return const AiFailure(AiFailureKind.unreadable);

    // The first *text* block. There may be thinking blocks ahead of it, so this cannot take
    // content[0]; with a schema attached, that text block is the whole answer.
    String? text;
    for (final block in content) {
      if (block is Map && block['type'] == 'text' && block['text'] is String) {
        text = block['text'] as String;
        break;
      }
    }

    final usage = decoded['usage'];
    return HttpAiAdapter.payloadOf(
      text,
      cachedTokens: usage is Map ? (usage['cache_read_input_tokens'] as num?)?.toInt() : null,
    );
  }
}

/// The request body, built separately so a test can assert its shape without a client.
///
/// The ordering here is the caching design, not house style. `system` renders before `messages`,
/// and a cache prefix matches byte for byte from the start — so the block that never changes goes
/// first and carries the breakpoint, and everything that varies per request goes after it. Move
/// anything volatile up into the first block and the prefix stops matching on every request,
/// which nothing in the app would ever report.
///
/// The breakpoint is only written when the request asks for one — see [AiRequest.cachePrefix] on
/// why a feature can be better off without it.
Map<String, dynamic> buildBody(AiRequest request, AiModel model) => {
      'model': model.id,
      'max_tokens': request.answerTokens,
      'system': [
        {
          'type': 'text',
          'text': request.systemPrefix,
          if (request.cachePrefix) 'cache_control': {'type': 'ephemeral'},
        },
        if (request.systemTail.isNotEmpty) {'type': 'text', 'text': request.systemTail},
      ],
      'messages': [
        {
          'role': 'user',
          'content': [
            if (request.jpeg != null)
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': 'image/jpeg',
                  'data': base64Encode(request.jpeg!),
                },
              },
            {'type': 'text', 'text': request.userText},
          ],
        },
      ],
      'output_config': {
        'format': {'type': 'json_schema', 'schema': request.schema},
        // A little arithmetic over a clear input, not deep reasoning — and the user is watching a
        // spinner. Omitted entirely for models that predate the parameter, which reject it.
        if (model.supportsEffort) 'effort': 'medium',
      },
      // No `thinking` key at all: it is adaptive by default on the current models, and the older
      // one in the table takes a different shape for it. No assistant prefill either — that is a
      // 400 on every model this app offers.
    };
