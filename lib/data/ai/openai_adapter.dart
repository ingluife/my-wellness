import 'dart:convert';

import '../../domain/ai/ai_provider.dart';
import 'ai_adapter.dart';

/// OpenAI's Responses API.
///
/// Verified against developers.openai.com in August 2026: this is `/v1/responses`, **not**
/// `/v1/chat/completions`. The differences are not cosmetic — messages go in `input` rather than
/// `messages`, content parts are `input_text` / `input_image` rather than `text` / `image_url`, an
/// image is a data URL rather than a `{url}` object, and the JSON schema hangs off `text.format`
/// rather than top-level `response_format`. Code written from memory of the chat-completions shape
/// is wrong in all five places.
class OpenAiAdapter extends HttpAiAdapter {
  OpenAiAdapter({required super.model, required super.keys, super.client});

  /// The GPT-5 family reasons, and reasoning tokens count against the same ceiling as the answer
  /// — so the request's answer budget is not the number to send. A limit the model's reasoning
  /// consumes before it reaches the JSON truncates the answer rather than shortening it, so this
  /// is added on top of whatever the feature asked for.
  static const reasoningHeadroom = 2500;

  @override
  String get providerId => 'openai';

  @override
  Uri get endpoint => Uri.parse('https://api.openai.com/v1/responses');

  @override
  Map<String, String> headers(String key) => {
        'content-type': 'application/json',
        'Authorization': 'Bearer $key',
      };

  @override
  Map<String, dynamic> body(AiRequest request) => buildOpenAiBody(request, model);

  @override
  AiResult parse(Map<String, dynamic> decoded) {
    final output = decoded['output'];
    if (output is! List) return const AiFailure(AiFailureKind.unreadable);

    // Reasoning items appear in `output` alongside the message, so this scans for the message
    // rather than indexing, the same way the Anthropic adapter steps past thinking blocks.
    for (final item in output) {
      if (item is! Map) continue;
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is Map && part['type'] == 'output_text' && part['text'] is String) {
          return HttpAiAdapter.payloadOf(part['text'] as String);
        }
      }
    }
    return const AiFailure(AiFailureKind.unreadable);
  }
}

/// The request body, split out so its shape can be asserted without a client.
/// There is no cache breakpoint to place here — OpenAI caches on its own terms and offers no
/// per-block control — so the stable and volatile halves are simply concatenated in order.
Map<String, dynamic> buildOpenAiBody(AiRequest request, AiModel model) => {
      'model': model.id,
      'max_output_tokens': request.answerTokens + OpenAiAdapter.reasoningHeadroom,
      'input': [
        {
          // A developer-role message, which outranks the user turn. The catalogue is instruction,
          // not conversation.
          'role': 'developer',
          'content': request.systemPrefix,
        },
        {
          'role': 'user',
          'content': [
            if (request.jpeg != null)
              {
                'type': 'input_image',
                // A data URL, not a {url: ...} object — the Responses API takes the base64 inline.
                'image_url': 'data:image/jpeg;base64,${base64Encode(request.jpeg!)}',
                'detail': 'auto',
              },
            {
              'type': 'input_text',
              'text': request.systemTail.isEmpty
                  ? request.userText
                  : '${request.systemTail}\n\n${request.userText}',
            },
          ],
        },
      ],
      'text': {
        'format': {
          'type': 'json_schema',
          // Required, and it is a name for the schema rather than anything the model sees.
          'name': request.schemaName,
          'schema': request.schema,
          'strict': true,
        },
      },
    };
