import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/ai/ai_adapter.dart';
import '../data/ai/ai_key_store.dart';
import '../data/ai/anthropic_adapter.dart';
import '../data/ai/gemini_adapter.dart';
import '../data/ai/openai_adapter.dart';
import '../data/models/app_state.dart';
import '../domain/ai/ai_provider.dart';
import '../platform/photo_capture.dart';
import 'app_state_provider.dart';

/// Where the AI seam is wired up, and the single place a widget test overrides to run the whole
/// feature without a network or a keychain.
///
/// Everything here is deliberately a `Provider` rather than a singleton: the rest of `lib/state`
/// keeps its platform objects as singletons (`Reminders.instance`, `ScreenWakeLock.instance`)
/// because they are genuinely process-wide, but an AI provider is chosen per profile and has to
/// be swappable in a test that builds the real app.

final aiKeyStoreProvider = Provider<AiKeyStore>((ref) => SecureAiKeyStore());

/// The camera and photo library. Overridden in widget tests with fixture bytes — a test cannot
/// open a camera, and the review sheet is the part most worth testing end to end.
final photoCaptureProvider = Provider<PhotoCapture>((ref) => ImagePickerCapture());

/// Which providers currently hold a key.
///
/// A future rather than a value because the keychain is asynchronous, and presence-only because
/// nothing above `lib/data/ai` is allowed to see a key. The settings screen watches it; so does
/// [aiMealPhotoProvider], which is why turning a key off makes the camera affordance disappear
/// rather than leaving a button that fails when tapped.
final aiConfiguredProvider = FutureProvider<Set<String>>(
  (ref) => ref.watch(aiKeyStoreProvider).configured(),
);

/// The adapter for [featureId], or [DisabledAi] when that feature cannot run.
///
/// Resolution order matters and is all negative: off, or no provider chosen, or no key for the
/// one chosen, or no adapter in this build — each of those is a reason to hand back [DisabledAi]
/// rather than something that will fail later. `isAvailable` is what the UI gates on, so a "no"
/// here is what keeps the entry point absent instead of dead.
///
/// Written once and shared by every feature's provider below. Each feature is configured
/// separately — its own switch, its own provider, its own model — so the gates run per feature;
/// what they must not do is drift apart, which is exactly what a second hand-copied set of them
/// would eventually do.
///
/// All three providers in [aiProviders] have an adapter behind them — see [adapterFor], which
/// `ai_adapter_multi_test.dart` guards against the picker and the switch drifting apart.
AiProvider _gate(Ref ref, String featureId) {
  final cfg = ref.watch(appStateProvider.select((s) => s.ai.features[featureId]?.copy()));
  if (cfg == null || !cfg.isOn) return const DisabledAi();

  final providerId = cfg.provider;
  if (providerId == null || !aiProviders.contains(providerId)) return const DisabledAi();

  // A key that is still being read counts as absent. The alternative — assuming availability
  // until proven otherwise — puts a button on screen that fails on the first tap.
  final configured = ref.watch(aiConfiguredProvider).value ?? const <String>{};
  if (!configured.contains(providerId)) return const DisabledAi();

  final model = modelFor(providerId, cfg.model);
  if (model == null) return const DisabledAi();

  // Constructed only once every gate above has passed — which is what makes "the app holds no
  // http client unless the user turned this on" an assertable claim rather than an intention.
  // (The connection test builds one too, but only for the moment a tap lasts, and it closes it.)
  final adapter = adapterFor(providerId, model, ref.watch(aiKeyStoreProvider));
  ref.onDispose(adapter.close);
  return adapter;
}

/// The provider that reads meal photographs.
final aiMealPhotoProvider = Provider<AiProvider>((ref) => _gate(ref, aiMealPhoto));

/// The provider that drafts workout routines.
final aiWorkoutPlanProvider = Provider<AiProvider>((ref) => _gate(ref, aiWorkoutPlan));

/// The adapter for [providerId], with no regard for whether the feature is switched on.
///
/// Shared by [aiMealPhotoProvider] and [aiProbeProvider] so there is one list of which id maps to
/// which adapter. A second copy of this switch is how a provider gets added to the picker and
/// forgotten in the test path.
HttpAiAdapter adapterFor(String providerId, AiModel model, AiKeyStore keys) =>
    switch (providerId) {
      'anthropic' => AnthropicAdapter(model: model, keys: keys),
      'google' => GeminiAdapter(model: model, keys: keys),
      'openai' => OpenAiAdapter(model: model, keys: keys),
      // Unreachable while aiProviders and this switch agree; a provider id from a newer build
      // arriving in an older one is the case that makes it reachable.
      _ => throw StateError('no adapter for $providerId'),
    };

/// Runs the settings screen's connection test against [providerId]: null when it worked.
///
/// A provider holding a function, rather than a method somewhere, for the same reason
/// [photoCaptureProvider] is one — it is the seam a widget test overrides to drive the settings
/// screen without a socket. The adapter it builds lives exactly as long as the request and is
/// closed either way, so a screen that is never tapped still holds no client.
///
/// The model it tests with is the one the user would actually spend money on: whatever is chosen
/// for [providerId] specifically — each provider keeps its own choice in `AiFeatureConfig.models`
/// now, so this reads straight off that regardless of which provider currently runs the feature.
/// Testing some other model would pass while the configured one 404s.
final aiProbeProvider = Provider<Future<AiFailureKind?> Function(String)>((ref) {
  return (providerId) async {
    if (!aiProviders.contains(providerId)) return AiFailureKind.notConfigured;

    final cfg = ref.read(appStateProvider).ai.features[aiMealPhoto];
    final model = modelFor(providerId, cfg?.models[providerId]);
    if (model == null) return AiFailureKind.notConfigured;

    final adapter = adapterFor(providerId, model, ref.read(aiKeyStoreProvider));
    try {
      return await adapter.probe();
    } finally {
      adapter.close();
    }
  };
});

/// The same test, against a key the user has typed but not yet saved.
///
/// The one place a key that never touched the keychain is allowed to exist at all, and only for
/// the lifetime of this one request: [MemoryAiKeyStore] holds it in a local variable, the adapter
/// reads it once, and both are discarded when the call returns. Nothing about this path writes to
/// [aiKeyStoreProvider] — testing must not be a backdoor around Save.
final aiProbeKeyProvider =
    Provider<Future<AiFailureKind?> Function(String providerId, String key)>((ref) {
  return (providerId, key) async {
    if (!aiProviders.contains(providerId)) return AiFailureKind.notConfigured;

    final cfg = ref.read(appStateProvider).ai.features[aiMealPhoto];
    final model = modelFor(providerId, cfg?.models[providerId]);
    if (model == null) return AiFailureKind.notConfigured;

    final adapter = adapterFor(providerId, model, MemoryAiKeyStore({providerId: key}));
    try {
      return await adapter.probe();
    } finally {
      adapter.close();
    }
  };
});
