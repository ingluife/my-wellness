import 'dart:convert';

import '../../domain/ai/ai_provider.dart';
import 'ai_adapter.dart';

/// Google's Gemini API, through `models.{id}:generateContent`.
///
/// **This file used to target `/v1beta/interactions`**, Google's newer unified endpoint, and the
/// shape here was written against its documentation. It was moved back deliberately, on evidence
/// rather than on taste: a key that worked against `generateContent` from another application was
/// answered with a flat HTTP 429 on every `interactions` request — both models, first request of
/// the day, with the account's own rate-limit dashboard showing 2 of 5 RPM and 1.33K of 250K TPM
/// as the 28-day peak. Nothing was being rate limited; `interactions` appears to bill against a
/// quota bucket a plain API key on the free tier does not hold (its own docs describe it as the
/// interface for *models and agents*, and the dashboard tracks agents as a separate category).
///
/// So the rule this file has always carried still stands, just pointed the other way: verify
/// against the live docs, never from memory. Every field below was checked against
/// ai.google.dev in August 2026, and the spellings are the ones the REST docs actually print —
/// `system_instruction`, `contents`/`parts`, `inline_data` with `mime_type`, and a
/// `generationConfig` holding `response_mime_type` / `response_schema`. Proto3 JSON accepts both
/// casings for every one of these; the documented example mixes them exactly as this does, so it
/// is copied rather than tidied.
class GeminiAdapter extends HttpAiAdapter {
  GeminiAdapter({required super.model, required super.keys, super.client});

  /// Gemini 3.7 Flash thinks, and thinking tokens count against the same ceiling as the answer —
  /// so the request's answer budget is not the number to send. A limit that a model's reasoning
  /// eats before it reaches the JSON truncates the answer rather than shortening it, so this is
  /// added on top of whatever the feature asked for.
  static const reasoningHeadroom = 2500;

  @override
  String get providerId => 'google';

  /// The model id is in the path here, not in the body — the one structural difference from the
  /// other two adapters, and the reason this is a getter that reads `model`.
  @override
  Uri get endpoint => Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/${model.id}:generateContent');

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
    // A prompt refused before the model ever ran comes back as a 200 with no candidates at all,
    // so this has to be checked before reaching for them.
    final feedback = decoded['promptFeedback'];
    if (feedback is Map && feedback['blockReason'] != null) {
      return const AiFailure(AiFailureKind.refused);
    }

    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      return const AiFailure(AiFailureKind.unreadable);
    }

    final first = candidates.first;
    if (first is! Map) return const AiFailure(AiFailureKind.unreadable);

    // SAFETY and friends are a refusal, not an unreadable answer — the user can act on one and
    // not on the other. MAX_TOKENS falls through to the text below, which will be truncated JSON
    // and fails to decode, which is the honest outcome for a half-written answer.
    if (first['finishReason'] == 'SAFETY' || first['finishReason'] == 'PROHIBITED_CONTENT') {
      return const AiFailure(AiFailureKind.refused);
    }

    final content = first['content'];
    if (content is! Map) return const AiFailure(AiFailureKind.unreadable);
    final parts = content['parts'];
    if (parts is! List) return const AiFailure(AiFailureKind.unreadable);

    // Thinking models put their reasoning in parts flagged `thought`, ahead of the answer. Scan
    // past those rather than indexing, the same way the Anthropic adapter steps past its
    // thinking blocks.
    for (final part in parts) {
      if (part is! Map || part['thought'] == true) continue;
      if (part['text'] is String) {
        return HttpAiAdapter.payloadOf(part['text'] as String);
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
      // An object with `parts`, not a bare string — the REST shape for this differs from the
      // SDKs', which take a plain string and wrap it for you.
      'system_instruction': {
        'parts': [
          {'text': request.systemPrefix}
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            if (request.jpeg != null)
              {
                'inline_data': {
                  'mime_type': 'image/jpeg',
                  'data': base64Encode(request.jpeg!),
                },
              },
            {
              'text': request.systemTail.isEmpty
                  ? request.userText
                  : '${request.systemTail}\n\n${request.userText}',
            },
          ],
        },
      ],
      // camelCase throughout, matching the REST reference's own `responseSchema` example and a
      // known-good request from another application against this same API. Proto3 JSON accepts
      // either casing, so this is not a fix for anything — it is one fewer difference from a
      // request that is known to work, which is worth more here than internal consistency with
      // the snake_case fields above.
      'generationConfig': {
        'responseMimeType': 'application/json',
        // Translated, not passed through — see [geminiSchema].
        'responseSchema': geminiSchema(request.schema),
        'maxOutputTokens': request.answerTokens + GeminiAdapter.reasoningHeadroom,
      },
    };

/// A request's schema in the dialect `response_schema` actually speaks.
///
/// `response_schema` is not JSON Schema. It is Google's OpenAPI-3.0-derived `Schema` message, and
/// the REST reference's own example spells its types in upper case — `"type": "ARRAY"`,
/// `"OBJECT"`, `"STRING"`. Sending the lower-case JSON Schema spelling that Anthropic and OpenAI
/// both want is a 400 from every model at once, which reads in the app as "the model may no
/// longer exist" and sends you looking at the model table for a fault that is in this line.
///
/// So the shared schema stays canonical JSON Schema — it is the one the other two adapters send
/// unmodified, and the one the sanitiser is written against — and the conversion lives here,
/// which is the only place that needs it. Two changes, both narrow:
///
///  1. **`type` values are upper-cased.** Only when the value is a string, so a property that
///     happened to be *named* `type` (whose value is a nested schema object) is untouched.
///  2. **`additionalProperties` is dropped.** It is a JSON Schema keyword the `Schema` message
///     has no field for, and an unknown field is the other way this request 400s. Losing it only
///     loosens a constraint — `meal_photo_sanitize.dart` ignores keys it does not know anyway, so
///     nothing downstream depends on the model being forbidden to invent one.
Object? geminiSchema(Object? node) {
  if (node is Map) {
    return {
      for (final e in node.entries)
        if (e.key != 'additionalProperties')
          e.key: e.key == 'type' && e.value is String
              ? (e.value as String).toUpperCase()
              : geminiSchema(e.value),
    };
  }
  if (node is List) return [for (final v in node) geminiSchema(v)];
  return node;
}
