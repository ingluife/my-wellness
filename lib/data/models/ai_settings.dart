import 'json.dart';

/// Which AI provider answers which feature, and whether the feature is on at all.
///
/// The keys themselves are **not here**. This object is serialised into SharedPreferences, into
/// the plaintext `opengym-state.json` mirror, and into every backup the user exports through the
/// share sheet. An API key in any of those places is a secret sitting in three files the user
/// reasonably believes are theirs to email to themselves. Keys live in the platform keychain
/// behind `AiKeyStore`; what lives here is only ever a choice, never a credential.
///
/// Like `nutrition` and `meals`, `ai` is a key openGym has no default for, so it follows the same
/// contract: absent until the feature is actually used, so a profile that never opened it still
/// exports exactly the JSON openGym does. See AppState.toJson.

/// The features that can be pointed at a provider.
///
/// A list rather than an enum because these ids are written into the state, and an enum tempts a
/// future rename that would silently orphan everybody's setting.
const aiMealPhoto = 'mealPhoto';

const aiFeatures = <String>[aiMealPhoto];

/// English display names; these strings are the i18n keys.
const aiFeatureName = <String, String>{
  aiMealPhoto: 'Meal photo',
};

/// How one feature is set up.
///
/// Every field is nullable with a documented reading rather than carrying a default, following
/// [NutritionGoal] and `effort`: a profile that never chose has to stay distinguishable from one
/// that chose the value that happens to be the default, or the key can never be dropped again and
/// the state stops matching a fresh openGym export.
class AiFeatureConfig {
  AiFeatureConfig({this.on, this.provider, this.model, this.keepPhotos});

  /// null = never chosen, read as off.
  ///
  /// Opt-in is the whole design. This is the only feature in the app that sends anything off the
  /// phone, and a default of null-means-off is what makes an untouched profile behave exactly as
  /// it did before the feature existed.
  bool? on;

  /// 'anthropic' | 'google' | 'openai'. null = never chosen.
  String? provider;

  /// The model id, as the provider spells it. null = this build's default for [provider].
  ///
  /// Stored rather than derived because model ids are the one thing here with a price attached:
  /// a user who deliberately picked the cheap model must not silently get moved to the expensive
  /// one by an app update.
  String? model;

  /// Whether the photograph is kept on the phone after the meal is logged. Read only by the meal
  /// photo feature; a future feature with no photograph simply never writes it.
  ///
  /// null = never chosen, **read as yes** — the one field here that does not default to off, and
  /// deliberately so. Every other default in this class protects a user who has not opted in;
  /// this one belongs to a user who already has, and for them the picture is most of the point of
  /// having photographed the plate. It is bounded rather than unlimited: see
  /// `MealPhotoStore.retention`.
  bool? keepPhotos;

  bool get isDefault =>
      on == null && provider == null && model == null && keepPhotos == null;

  /// Whether this feature should actually run. Absent is off; that is the point.
  bool get isOn => on == true;

  /// Absent is yes — see [keepPhotos].
  bool get keepsPhotos => keepPhotos != false;

  factory AiFeatureConfig.fromJson(Map<String, dynamic> j) => AiFeatureConfig(
        on: j['on'] is bool ? j['on'] as bool : null,
        provider: asStr(j['provider']),
        model: asStr(j['model']),
        keepPhotos: j['keepPhotos'] is bool ? j['keepPhotos'] as bool : null,
      );

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    put(m, 'on', on);
    put(m, 'provider', provider);
    put(m, 'model', model);
    put(m, 'keepPhotos', keepPhotos);
    return m;
  }

  AiFeatureConfig copy() => AiFeatureConfig.fromJson(toJson());
}

/// The `ai` key: one entry per feature, and nothing derived.
class AiSettings {
  AiSettings({Map<String, AiFeatureConfig>? features, Map<String, dynamic>? extra})
      : features = features ?? {},
        extra = extra ?? {};

  /// Feature id -> how it is set up. Sparse: a feature nobody has touched has no entry.
  ///
  /// A map keyed by feature id rather than a field per feature, because this has to hold more
  /// features later and because an unknown id from a newer build then round-trips through [extra]
  /// for free — the same reasoning `AppState.extra` is built on.
  Map<String, AiFeatureConfig> features;

  /// Feature keys this build does not know about, carried through untouched.
  Map<String, dynamic> extra;

  /// The config for [id], created on demand so a caller can write to it directly.
  ///
  /// Creating on read is safe precisely because a fresh config is [AiFeatureConfig.isDefault], so
  /// merely looking at a feature never starts writing the key.
  AiFeatureConfig feature(String id) => features.putIfAbsent(id, AiFeatureConfig.new);

  /// Nothing has been set — the key is dropped entirely.
  bool get isDefault => features.values.every((f) => f.isDefault) && extra.isEmpty;

  factory AiSettings.fromJson(Map<String, dynamic> j) {
    final s = AiSettings();
    for (final e in j.entries) {
      if (aiFeatures.contains(e.key)) {
        if (e.value is Map) s.features[e.key] = AiFeatureConfig.fromJson(asMap(e.value));
      } else {
        s.extra[e.key] = e.value;
      }
    }
    return s;
  }

  Map<String, dynamic> toJson() {
    final m = <String, dynamic>{};
    // Written in the declared feature order rather than insertion order, so two states holding
    // the same settings serialise to the same bytes and a diff of two backups shows real changes.
    for (final id in aiFeatures) {
      final f = features[id];
      if (f != null && !f.isDefault) m[id] = f.toJson();
    }
    m.addAll(extra);
    return m;
  }

  AiSettings copy() => AiSettings.fromJson(toJson());
}
