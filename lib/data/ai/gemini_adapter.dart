import 'dart:convert';

import '../../domain/ai/ai_provider.dart';
import '../../domain/ai/meal_photo_prompt.dart';
import 'vision_adapter.dart';

/// Google's Gemini Interactions API.
///
/// Verified against ai.google.dev in August 2026, not recalled: Google replaced the older
/// `generateContent` shape — `contents` / `parts` / `inline_data`, camelCase `responseSchema` — with
/// `/v1beta/interactions`, a flat `input` array and snake_case `response_format`. Anything written
/// from memory of the previous API is wrong in every one of those places, so this file is worth
/// re-checking against the docs rather than eyeballing whenever it next fails.
class GeminiAdapter extends HttpVisionAdapter {
  GeminiAdapter({required super.model, required super.keys, super.client});

  /// Gemini 3.7 Flash thinks, and thinking tokens count against this ceiling — so it is set well
  /// above what the answer itself needs. A limit that a model's reasoning eats before it reaches
  /// the JSON truncates the answer rather than shortening it.
  static const maxOutputTokens = 4000;

  @override
  String get providerId => 'google';

  @override
  Uri get endpoint =>
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/interactions');

  @override
  Map<String, String> headers(String key) => {
        'content-type': 'application/json',
        // Not an Authorization bearer: Google takes the key in its own header.
        'x-goog-api-key': key,
      };

  @override
  Map<String, dynamic> body(AiRequest request) => buildGeminiBody(request, model);

  @override
  AiResult parse(Map<String, dynamic> decoded) {
    // The answer is nested two levels deeper than the other two providers: an interaction is a
    // list of steps, and the text sits in the content of the model_output step. Other step types
    // (tool calls, thoughts) can precede it, so this scans rather than indexing.
    final steps = decoded['steps'];
    if (steps is! List) return const AiFailure(AiFailureKind.unreadable);

    for (final step in steps) {
      if (step is! Map || step['type'] != 'model_output') continue;
      final content = step['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is Map && part['type'] == 'text' && part['text'] is String) {
          return HttpVisionAdapter.payloadOf(part['text'] as String);
        }
      }
    }
    return const AiFailure(AiFailureKind.unreadable);
  }
}

/// The request body, split out so its shape can be asserted without a client.
///
/// No prompt-cache breakpoint here, unlike Anthropic: Gemini caches implicitly and has no
/// per-block control to place, so the catalogue simply goes in `system_instruction` where it is
/// the stable prefix of every request anyway.
Map<String, dynamic> buildGeminiBody(AiRequest request, AiModel model) => {
      'model': model.id,
      'system_instruction':
          '${mealPhotoInstructions.trim()}\n\n<catalogue>\n${request.vocabulary}\n</catalogue>',
      'input': [
        {
          // Flat parts with a `data` field — not the `inline_data: {mime_type, data}` nesting the
          // old generateContent API used.
          'type': 'image',
          'mime_type': 'image/jpeg',
          'data': base64Encode(request.jpeg),
        },
        {
          'type': 'text',
          'text': '${buildRequestTail(
            languageName: request.language,
            customFoods: request.customFoods,
            hint: request.hint,
          )}\n\nRead this meal.',
        },
      ],
      'response_format': {
        'type': 'text',
        'mime_type': 'application/json',
        'schema': mealPhotoSchema,
      },
      'generation_config': {'max_output_tokens': GeminiAdapter.maxOutputTokens},
    };
