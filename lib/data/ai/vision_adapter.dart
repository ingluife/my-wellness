import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../domain/ai/ai_provider.dart';
import 'ai_key_store.dart';

/// What all three provider adapters share: one POST, one timeout, and one set of rules about
/// never leaking anything.
///
/// The three APIs disagree about almost everything — endpoint, auth header, how an image is
/// attached, how a JSON schema is imposed, where the answer sits in the response. What they do not
/// disagree about is the handling around that, and it is the part with the security properties, so
/// it lives in exactly one place:
///
///  1. **Nothing throws across the seam.** Every failure is an [AiFailure]. An exception escaping
///     an adapter carries a stack trace and possibly the request body, and the request body is a
///     photograph of the user's kitchen.
///  2. **The key goes in a header and nowhere else.** Read per request, never stored on the
///     object, never in a message.
///  3. **No provider response body is ever surfaced.** Providers echo request fragments back in
///     their errors. Map the status code and discard the rest.
abstract class HttpVisionAdapter implements AiVisionProvider {
  HttpVisionAdapter({
    required this.model,
    required AiKeyStore keys,
    http.Client? client,
  })  : _keys = keys,
        _client = client ?? http.Client();

  /// Long enough for a slow mobile connection to push ~150 KB, short enough that somebody staring
  /// at a spinner gets an answer either way.
  static const timeout = Duration(seconds: 45);

  final AiModel model;
  final AiKeyStore _keys;
  final http.Client _client;

  /// Which key in the store this adapter needs — 'anthropic' | 'google' | 'openai'.
  String get providerId;

  Uri get endpoint;

  /// Auth and content-type. [key] is live here and must not travel any further.
  Map<String, String> headers(String key);

  Map<String, dynamic> body(AiRequest request);

  /// The decoded 200 body, as this provider shapes it, turned into a result.
  ///
  /// Returns the raw payload the model produced, unvalidated — sanitising is
  /// `meal_photo_sanitize.dart`'s job, it is pure, and it is where every bound is tested.
  AiResult parse(Map<String, dynamic> decoded);

  @override
  bool get isAvailable => true;

  @override
  String get label => model.label;

  /// Aborts an in-flight request. What the sheet's Cancel button reaches, so cancelling actually
  /// stops the upload rather than only hiding the spinner in front of it.
  void close() => _client.close();

  @override
  Future<AiResult> readMeal(AiRequest request) async {
    final key = await _keys.read(providerId);
    if (key == null) return const AiFailure(AiFailureKind.notConfigured);

    final (res, failed) = await _send(key, request);
    if (failed != null) return AiFailure(failed);

    try {
      final decoded = jsonDecode(res!.body);
      if (decoded is! Map) return const AiFailure(AiFailureKind.unreadable);
      return parse(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // Deliberately bare, and deliberately silent. Whatever this was, it happened with a key and
      // a photograph in scope, and no diagnostic is worth the risk of quoting either.
      return const AiFailure(AiFailureKind.unreadable);
    }
  }

  /// The settings screen's connection test: null when the provider accepted the request, otherwise
  /// what to tell the user.
  ///
  /// It sends [probeRequest] to the **real** endpoint, through the real headers and the real body
  /// builder, and judges the outcome on the status code alone — what came back does not matter,
  /// only that the provider was willing to answer.
  ///
  /// Deliberately not a free list-models call. That would prove the key is a key and nothing else.
  /// This proves the four things that actually break: the key is accepted, this build's request
  /// shape is still one the provider parses, the model id in the picker still exists, and the
  /// response schema is still one it accepts. Provider APIs move — the model table and the three
  /// adapter files all carry warnings saying so — and every one of those failures reads to a user
  /// as "the app is broken", which is exactly what a key check would sail past.
  ///
  /// The price of that is a real inference call, of the order of a US cent. The screen says so.
  Future<AiFailureKind?> probe() async {
    final key = await _keys.read(providerId);
    if (key == null) return AiFailureKind.notConfigured;
    final (_, failed) = await _send(key, probeRequest);
    return failed;
  }

  /// One POST, and every way it can go wrong mapped to a kind.
  ///
  /// Both callers go through here so rule 1 and rule 3 above hold in a single place: nothing
  /// throws out of it, and nothing it returns carries a byte of what the provider said.
  Future<(http.Response?, AiFailureKind?)> _send(String key, AiRequest request) async {
    try {
      final res = await _client
          .post(endpoint, headers: headers(key), body: jsonEncode(body(request)))
          .timeout(timeout);
      return (res, res.statusCode == 200 ? null : kindOfStatus(res.statusCode));
    } on TimeoutException {
      return (null, AiFailureKind.timeout);
    } on SocketException {
      return (null, AiFailureKind.offline);
    } on http.ClientException {
      // A connection dropped mid-flight, and also a request aborted by close().
      return (null, AiFailureKind.offline);
    } catch (_) {
      // As above: bare and silent, because a key and a photograph were in scope.
      return (null, AiFailureKind.unreadable);
    }
  }

  /// What [probe] sends: an ordinary meal read, around a 64x64 flat grey photograph and an empty
  /// catalogue.
  ///
  /// Small on purpose in both halves. The image is a handful of tokens rather than the ~1,050 a
  /// real plate costs, and an empty vocabulary keeps the prompt at a few hundred tokens instead of
  /// a few thousand — so the test lands at a fraction of what a photo costs while still travelling
  /// the identical code path. The model will answer that this is not food, and [probe] does not
  /// read the answer.
  static final probeRequest = AiRequest(
    jpeg: _probeJpeg,
    vocabulary: '',
    customFoods: '',
    language: 'English',
  );

  /// 64x64, mid-grey, quality 40, already stripped — 305 bytes.
  ///
  /// Baked in rather than generated: there is no JPEG encoder in this build (see
  /// `photo_capture.dart` on why the `image` package is deliberately absent), and a literal is
  /// the honest way to say that this never touches a camera, a file or a scrubber.
  static final _probeJpeg = base64Decode(
      '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDABQODxIPDRQSEBIXFRQYHjIhHhwcHj0sLiQySUBMS0dARkVQWnNi'
      'UFVtVkVGZIhlbXd7gYKBTmCNl4x9lnN+gXz/2wBDARUXFx4aHjshITt8U0ZTfHx8fHx8fHx8fHx8fHx8fHx8'
      'fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHx8fHz/wAARCABAAEADASIAAhEBAxEB/8QAFAABAAAAAAAA'
      'AAAAAAAAAAAAAP/EABQQAQAAAAAAAAAAAAAAAAAAAAD/xAAUAQEAAAAAAAAAAAAAAAAAAAAA/8QAFBEBAAAA'
      'AAAAAAAAAAAAAAAAAP/aAAwDAQACEQMRAD8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/9k=');

  /// Shared because all three use ordinary HTTP semantics for these.
  static AiFailureKind kindOfStatus(int status) => switch (status) {
        401 || 403 => AiFailureKind.badKey,
        429 => AiFailureKind.rateLimited,
        >= 500 => AiFailureKind.providerDown,
        // Ordered after the three above, so this catches only what they left: a 4xx that is about
        // the request rather than the key. Almost always a retired model id or a request shape the
        // provider has moved past — see [AiFailureKind.rejected].
        >= 400 => AiFailureKind.rejected,
        _ => AiFailureKind.unreadable,
      };

  /// Parses the model's answer text, which every provider delivers as a JSON string.
  ///
  /// Even with a schema attached the payload arrives as text that still has to be decoded, and a
  /// model can still return prose when something has gone wrong at its end.
  static AiResult payloadOf(String? text, {int? cachedTokens}) {
    if (text == null) return const AiFailure(AiFailureKind.unreadable);
    try {
      return AiDraft(jsonDecode(text), cachedTokens: cachedTokens);
    } catch (_) {
      return const AiFailure(AiFailureKind.unreadable);
    }
  }
}
