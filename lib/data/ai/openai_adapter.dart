import 'dart:convert';

import '../../domain/ai/ai_provider.dart';
import '../../domain/ai/meal_photo_prompt.dart';
import 'vision_adapter.dart';

/// OpenAI's Responses API.
///
/// Verified against developers.openai.com in August 2026: this is `/v1/responses`, **not**
/// `/v1/chat/completions`. The differences are not cosmetic — messages go in `input` rather than
/// `messages`, content parts are `input_text` / `input_image` rather than `text` / `image_url`, an
/// image is a data URL rather than a `{url}` object, and the JSON schema hangs off `text.format`
/// rather than top-level `response_format`. Code written from memory of the chat-completions shape
/// is wrong in all five places.
class OpenAiAdapter extends HttpVisionAdapter {
  OpenAiAdapter({required super.model, required super.keys, super.client});

  /// The GPT-5 family reasons, and reasoning tokens count against this ceiling — so it sits well
  /// above what the answer needs. A limit the model's reasoning consumes before it reaches the
  /// JSON truncates the answer rather than shortening it.
  static const maxOutputTokens = 4000;

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
          return HttpVisionAdapter.payloadOf(part['text'] as String);
        }
      }
    }
    return const AiFailure(AiFailureKind.unreadable);
  }
}

/// The request body, split out so its shape can be asserted without a client.
Map<String, dynamic> buildOpenAiBody(AiRequest request, AiModel model) => {
      'model': model.id,
      'max_output_tokens': OpenAiAdapter.maxOutputTokens,
      'input': [
        {
          // A developer-role message, which outranks the user turn. The catalogue is instruction,
          // not conversation.
          'role': 'developer',
          'content':
              '${mealPhotoInstructions.trim()}\n\n<catalogue>\n${request.vocabulary}\n</catalogue>',
        },
        {
          'role': 'user',
          'content': [
            {
              'type': 'input_image',
              // A data URL, not a {url: ...} object — the Responses API takes the base64 inline.
              'image_url': 'data:image/jpeg;base64,${base64Encode(request.jpeg)}',
              'detail': 'auto',
            },
            {
              'type': 'input_text',
              'text': '${buildRequestTail(
                languageName: request.language,
                customFoods: request.customFoods,
                hint: request.hint,
              )}\n\nRead this meal.',
            },
          ],
        },
      ],
      'text': {
        'format': {
          'type': 'json_schema',
          // Required, and it is a name for the schema rather than anything the model sees.
          'name': 'meal_photo',
          'schema': mealPhotoSchema,
          'strict': true,
        },
      },
    };
