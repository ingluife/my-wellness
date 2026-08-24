import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_state.dart';

/// Where the training log lives.
///
/// This is the user's only copy, so it does not depend on one store alone. Every write goes to
/// preferences immediately and, debounced, to a JSON file in the app's private data directory.
/// The file is the durable copy: the original ships the same pair because iOS is allowed to
/// evict WebView storage under pressure, and the same reasoning holds for any single store —
/// two independent copies restore each other.
///
/// The file is named `opengym-state.json` and holds the same JSON openGym writes, so a device
/// backup taken from either app can be dropped into the other.
class StateRepository {
  StateRepository({SharedPreferences? prefs, Directory? dir}) : _prefs = prefs, _dir = dir;

  static const prefsKey = 'gym_state_v1';
  static const fileName = 'opengym-state.json';
  static const _debounce = Duration(milliseconds: 800);

  SharedPreferences? _prefs;
  Directory? _dir;
  Timer? _saveTimer;
  AppState? _pending;

  Future<SharedPreferences> get _p async => _prefs ??= await SharedPreferences.getInstance();

  Future<File> get _file async {
    _dir ??= await getApplicationDocumentsDirectory();
    return File('${_dir!.path}/$fileName');
  }

  /// Read the local copy. Never throws: unreadable state is treated as no state, because
  /// failing to start is worse than starting empty with the file mirror still on disk.
  Future<AppState> loadLocal() async {
    try {
      final raw = (await _p).getString(prefsKey);
      if (raw != null) return AppState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {/* fall through to the defaults */}
    return AppState.defaults();
  }

  /// Read the file mirror, or null if there is not one yet.
  Future<AppState?> loadMirror() async {
    try {
      final f = await _file;
      if (!f.existsSync()) return null;
      return AppState.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      // First launch, or unreadable — the preferences copy takes over.
      return null;
    }
  }

  /// Resolve the two copies at boot.
  ///
  /// The mirror wins when it is newer, or when the local copy holds nothing worth keeping.
  /// A first run after updating from a version without the mirror seeds it instead.
  Future<AppState> boot() async {
    final local = await loadLocal();
    final saved = await loadMirror();
    if (saved != null && (!local.hasData || (saved.ts ?? 0) >= (local.ts ?? 0))) {
      await save(saved, immediate: true);
      return saved;
    }
    if (local.hasData) unawaited(_writeMirror(local));
    return local;
  }

  /// Persist [state]. Preferences are written synchronously with the call; the mirror is
  /// debounced, since a set row can fire this on every tap of a stepper.
  Future<void> save(AppState state, {bool immediate = false}) async {
    final json = jsonEncode(state.toJson());
    await (await _p).setString(prefsKey, json);
    _pending = state;
    _saveTimer?.cancel();
    if (immediate) {
      await flush();
    } else {
      _saveTimer = Timer(_debounce, flush);
    }
  }

  /// Write the mirror now.
  ///
  /// Called when the app is backgrounded — often the last thing that happens before the OS
  /// kills it, and the point at which a debounced write would be lost.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final s = _pending;
    _pending = null;
    if (s != null) await _writeMirror(s);
  }

  Future<void> _writeMirror(AppState state) async {
    try {
      await (await _file).writeAsString(jsonEncode(state.toJson()), flush: true);
    } catch (_) {
      // Keep the preferences copy; nothing the user could act on.
    }
  }

  /// Cancels the pending mirror write without performing it.
  ///
  /// For teardown only — a debounced save that outlives the thing that scheduled it is a
  /// dangling timer, and in a test it is a failure.
  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _pending = null;
  }

  /// Everything a reset leaves behind on this device.
  Future<void> clear() async {
    _saveTimer?.cancel();
    _pending = null;
    await (await _p).remove(prefsKey);
    try {
      final f = await _file;
      if (f.existsSync()) await f.delete();
    } catch (_) {/* already gone */}
  }
}
