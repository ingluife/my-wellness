import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the user's API keys live, which is deliberately nowhere near [AppState].
///
/// Everything else this app persists goes through `StateRepository`: SharedPreferences, plus a
/// plaintext `opengym-state.json` mirror in the documents directory, plus a copy in every backup
/// the user exports through the share sheet. That is exactly right for a training log and exactly
/// wrong for a credential. So the keys go to the platform keychain instead, and nothing above this
/// file ever holds one — the adapter reads it immediately before a request and does not retain it.
///
/// The interface exists so the settings screen and its widget test can talk to the same thing
/// without a mocking library, following the constructor-injection convention the rest of the repo
/// uses. [MemoryAiKeyStore] is the test double and lives here rather than under test/ so the
/// contract and its fake cannot drift apart.
abstract interface class AiKeyStore {
  /// The key for [providerId], or null when none is set.
  Future<String?> read(String providerId);

  /// Stores [key], or clears it when [key] is null or blank.
  Future<void> write(String providerId, String? key);

  /// Which providers have a key — presence only, never the value.
  ///
  /// This is what the settings screen and `isAvailable` are allowed to ask. A screen that needed
  /// the key itself to decide what to render would mean the secret had left this layer.
  Future<Set<String>> configured();

  /// Forgets every key. Called by Settings -> Reset everything.
  Future<void> clear();
}

/// Keychain on iOS, EncryptedSharedPreferences on Android.
class SecureAiKeyStore implements AiKeyStore {
  SecureAiKeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              // Deliberately the plain default constructor. `encryptedSharedPreferences: true` is
              // the incantation every example still shows, but it is deprecated as of 10.x and
              // ignored — Google deprecated the Jetpack Security library behind it. The default
              // is now the stronger path (AES-GCM data, RSA-OAEP key wrapping) and passing the
              // old flag would be noise that stops compiling at 11.x.
              aOptions: AndroidOptions(),
              // `this_device`, not the default: a key stored under a synchronising accessibility
              // class rides the user's iCloud Keychain to every other device on their Apple ID.
              // For an app whose promise is that things stay on this phone, silently syncing a
              // credential off it would be the wrong default even though it is the convenient one.
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  static String _slot(String providerId) => 'ai.key.$providerId';

  @override
  Future<String?> read(String providerId) async {
    // Never throws. A keychain that cannot be read is a feature that is unavailable, not an app
    // that fails to start — the same reasoning StateRepository's read paths are built on.
    try {
      final v = await _storage.read(key: _slot(providerId));
      return (v == null || v.isEmpty) ? null : v;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String providerId, String? key) async {
    final trimmed = key?.trim();
    try {
      if (trimmed == null || trimmed.isEmpty) {
        await _storage.delete(key: _slot(providerId));
      } else {
        await _storage.write(key: _slot(providerId), value: trimmed);
      }
    } catch (_) {
      // Nothing useful to say and nowhere safe to say it — an error message that quoted the
      // value would put the key in a log.
    }
  }

  @override
  Future<Set<String>> configured() async {
    try {
      final all = await _storage.readAll();
      return {
        for (final e in all.entries)
          if (e.key.startsWith('ai.key.') && e.value.isNotEmpty) e.key.substring(7)
      };
    } catch (_) {
      return const {};
    }
  }

  @override
  Future<void> clear() async {
    try {
      for (final id in await configured()) {
        await _storage.delete(key: _slot(id));
      }
    } catch (_) {
      // As above.
    }
  }
}

/// The in-memory double the tests inject. Same contract, no platform channel.
class MemoryAiKeyStore implements AiKeyStore {
  MemoryAiKeyStore([Map<String, String>? seed]) : _keys = {...?seed};

  final Map<String, String> _keys;

  @override
  Future<String?> read(String providerId) async => _keys[providerId];

  @override
  Future<void> write(String providerId, String? key) async {
    final trimmed = key?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      _keys.remove(providerId);
    } else {
      _keys[providerId] = trimmed;
    }
  }

  @override
  Future<Set<String>> configured() async => _keys.keys.toSet();

  @override
  Future<void> clear() async => _keys.clear();
}
