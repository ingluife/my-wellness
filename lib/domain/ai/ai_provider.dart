import 'dart:typed_data';

/// The seam every AI feature talks through, and the one place a network call is allowed to exist.
///
/// Shaped like `AuthRepository`, and for the same reason: `isAvailable` is what makes an entry
/// point *absent* rather than a dead button, so a build with no key configured behaves exactly as
/// the app did before this feature existed.
///
/// Two rules the adapters must hold to, both of which are about a secret rather than about style:
///
///  1. **Nothing throws across this seam.** Every failure is an [AiFailure], because an exception
///     escaping an adapter would carry a stack trace and possibly a request body, and the request
///     body has the user's photograph in it.
///  2. **No provider response body is ever surfaced.** Providers echo request fragments in error
///     messages. Map the status code to a [AiFailureKind] and discard the rest.

/// Which providers this build knows how to talk to.
///
/// Ids are written into `AppState.ai`, so they are permanent — a rename orphans everybody's
/// setting. 'google' rather than 'gemini' because the id names the account the key belongs to,
/// which outlives the model brand.
const aiProviders = <String>['anthropic', 'google', 'openai'];

/// English display names. Proper nouns: these do **not** go through `t()`.
const aiProviderName = <String, String>{
  'anthropic': 'Anthropic',
  'google': 'Google',
  'openai': 'OpenAI',
};

/// What one photograph costs to read, so the settings screen can say so before the user commits.
///
/// Dollars per million tokens, input and output, as published by the provider. These move, and
/// the screen says as much rather than presenting them as a quote.
typedef ModelPrice = ({double inPerM, double outPerM});

/// A model the user can pick, per provider.
class AiModel {
  const AiModel(this.id, this.label, this.price, {this.supportsEffort = true});

  /// Exactly as the provider spells it — this string goes on the wire.
  final String id;

  /// Proper noun; not translated.
  final String label;

  final ModelPrice price;

  /// Whether Anthropic's `output_config.effort` is accepted. Read only by the Anthropic adapter;
  /// the other two providers spell reasoning control differently and ignore this.
  ///
  /// Not a detail that can be skipped: the current Claude models take it, but Haiku 4.5 predates
  /// it and **rejects the request outright** rather than ignoring it. Sending it to every model
  /// would mean the cheapest option in the picker is the one that never works.
  final bool supportsEffort;

  /// Rough dollars for one meal photo: ~1,050 image tokens + ~2k of prompt, ~400 out.
  ///
  /// Deliberately an estimate and rounded as one. The honest thing to show a user who is about to
  /// spend their own money is an order of magnitude, not a figure that looks like a bill.
  double get perPhoto => (3050 * price.inPerM + 400 * price.outPerM) / 1000000;
}

/// The models offered per provider, most capable first so the picker reads as a ladder.
///
/// Every id and price here was checked against the provider's own documentation in August 2026,
/// not recalled. That matters more than it sounds: model ids turn over every few months, a wrong
/// one is a 404 the user reads as "this app is broken", and a wrong price is a number the app
/// quotes before spending someone's money. Re-check this table rather than extending it by
/// pattern — a plausible-looking id is not a real one.
///
/// Prices are dollars per million tokens, input and output.
const aiModels = <String, List<AiModel>>{
  'anthropic': [
    AiModel('claude-opus-5', 'Claude Opus 5', (inPerM: 5, outPerM: 25)),
    AiModel('claude-sonnet-5', 'Claude Sonnet 5', (inPerM: 3, outPerM: 15)),
    // Predates output_config.effort and rejects it outright — see [AiModel.supportsEffort].
    AiModel('claude-haiku-4-5', 'Claude Haiku 4.5', (inPerM: 1, outPerM: 5),
        supportsEffort: false),
  ],
  'google': [
    AiModel('gemini-3.1-pro-preview', 'Gemini 3.1 Pro', (inPerM: 2, outPerM: 12)),
    // Promotional pricing through 2026-12-31; doubles to 1.50/7.50 on 2027-01-01. The screen
    // says prices are the provider's and move, which is the honest way to carry that.
    AiModel('gemini-3.7-flash', 'Gemini 3.7 Flash', (inPerM: 0.75, outPerM: 3.75)),
  ],
  'openai': [
    AiModel('gpt-5.6-sol', 'GPT-5.6 Sol', (inPerM: 4, outPerM: 20)),
    AiModel('gpt-5.6-terra', 'GPT-5.6 Terra', (inPerM: 2, outPerM: 12)),
    AiModel('gpt-5.6-luna', 'GPT-5.6 Luna', (inPerM: 0.20, outPerM: 1.20)),
  ],
};

/// The default model for [providerId] — the first in its table.
AiModel? defaultModelFor(String providerId) => aiModels[providerId]?.firstOrNull;

/// Resolves a stored model id back to its entry, falling back to the provider's default.
///
/// A stored id this build no longer offers resolves to the default rather than to nothing: an app
/// update that retires a model must not leave the feature broken until the user visits settings.
AiModel? modelFor(String providerId, String? modelId) {
  final table = aiModels[providerId];
  if (table == null || table.isEmpty) return null;
  return table.where((m) => m.id == modelId).firstOrNull ?? table.first;
}

/// One meal photograph, and everything the prompt needs around it.
class AiRequest {
  const AiRequest({
    required this.jpeg,
    required this.vocabulary,
    required this.customFoods,
    this.language = 'en',
    this.hint,
  });

  /// The photograph, already downscaled and stripped of metadata. An adapter never resizes and
  /// never scrubs — by the time bytes reach one, both have happened.
  final Uint8List jpeg;

  /// The catalogue block. Stable across requests, which is what makes it cacheable.
  final String vocabulary;

  /// The user's own foods, as a second block. Volatile, so it must sit *after* the cache
  /// breakpoint rather than inside the prefix.
  final String customFoods;

  /// The UI language, so names come back in something the user reads.
  final String language;

  /// Anything the user typed to help — "the rice is a big portion".
  final String? hint;
}

/// Why a read failed. One case per thing the sheet has to say differently.
enum AiFailureKind {
  /// No key for the chosen provider, or the feature is off.
  notConfigured,

  /// No route to the host.
  offline,

  /// 401 / 403 — the key was refused.
  badKey,

  /// 429.
  rateLimited,

  /// 5xx.
  providerDown,

  /// A 4xx that is not about the key or the rate — the provider read the request and turned it
  /// down.
  ///
  /// Its own case because of what causes it in practice: a model id this build offers and the
  /// provider has retired, or a request shape that has moved on. Both are faults in the app, and
  /// folding them into [unreadable] would send the user looking at their photograph for them.
  /// This is the one failure a connection test exists to find.
  rejected,

  timeout,

  /// A 200 that could not be read as the agreed shape.
  unreadable,

  /// The provider's safety classifiers declined the photograph.
  ///
  /// Its own case rather than folded into [unreadable] because it is not a fault the user can fix
  /// by retrying, and telling them the answer was unreadable would send them round that loop.
  refused,

  /// The user backed out. Renders nothing.
  cancelled,
}

/// What the model returned, or why it didn't.
sealed class AiResult {
  const AiResult();
}

/// A successful read. [raw] is the decoded JSON exactly as it arrived — **unvalidated**.
///
/// Deliberately not a parsed draft. Sanitising is `meal_photo_sanitize.dart`'s job, it is pure,
/// and it is where every bound is unit-tested; an adapter that pre-digested the answer would move
/// that logic somewhere a socket is needed to test it.
class AiDraft extends AiResult {
  const AiDraft(this.raw, {this.cachedTokens});

  final Object? raw;

  /// `usage.cache_read_input_tokens`, when the provider reports it. Diagnostic only: it is the
  /// one way to tell whether the prompt prefix is actually being cached, which is otherwise
  /// invisible until a bill arrives.
  final int? cachedTokens;
}

class AiFailure extends AiResult {
  const AiFailure(this.kind);

  final AiFailureKind kind;
}

abstract interface class AiVisionProvider {
  /// Whether a photo read can be attempted at all — feature on, provider chosen, key present.
  bool get isAvailable;

  /// What to show while it thinks: 'Claude Opus 5'. A proper noun, not translated.
  String get label;

  Future<AiResult> readMeal(AiRequest request);
}

/// What this build ships with until the user sets a key up.
///
/// It is not a stub in the sense of being unfinished — it is the correct behaviour for an app
/// whose premise is that nothing leaves the phone. Replacing it is a choice the *user* makes, in
/// settings, with their own account. That is a stronger version of the sentence
/// `LocalOnlyAuth` carries, and it is the reason this feature can exist here at all.
class DisabledAi implements AiVisionProvider {
  const DisabledAi();

  @override
  bool get isAvailable => false;

  @override
  String get label => '';

  @override
  Future<AiResult> readMeal(AiRequest request) async =>
      const AiFailure(AiFailureKind.notConfigured);
}
