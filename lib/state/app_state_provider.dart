import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/app_state.dart';
import '../data/repositories/state_repository.dart';
import '../domain/exercises.dart';
import '../domain/format.dart';
import '../domain/i18n.dart';
import '../platform/reminders.dart';
import '../platform/wake_lock.dart';

final stateRepositoryProvider = Provider<StateRepository>((ref) {
  final repo = StateRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// The whole app, as one object.
///
/// Mirrors `useStore` in the original: a single [AppState] that every screen reads and every
/// action mutates through [update], which hands the producer a deep clone and persists the
/// result. Working on a clone is what makes the mutation style safe — a widget holding the
/// previous state sees an object nobody else is writing to.
class AppStateController extends Notifier<AppState> {
  StateRepository get _repo => ref.read(stateRepositoryProvider);

  @override
  AppState build() => AppState.defaults();

  /// Restore from disk, register the profile's custom exercises and apply its language.
  Future<void> boot() async {
    final s = await _repo.boot();
    Exercises.instance.registerCustom(s.customEx);
    await I18n.instance.setLang(s.lang);

    // Re-stamp the reminder's timezone on every launch — keeps it correct if you are
    // travelling, without needing to revisit Settings.
    final tz = localTZ();
    if (s.reminder.on && s.reminder.tz != tz) s.reminder.tz = tz;

    state = s;
    if (s.reminder.on) Reminders.instance.sync(s);
    ScreenWakeLock.instance.set(s.active != null && s.keepAwake);
  }

  /// Mutate a draft of the state, then persist it.
  ///
  /// `update((s) { s.routines.add(r); })` — the same shape as the producer functions the
  /// original passes to its store, so the porting of every action is a transcription rather
  /// than a redesign.
  void update(void Function(AppState s) mutate) {
    final draft = state.copy();
    mutate(draft);
    _persist(draft);
  }

  /// Replace the state wholesale — a backup import, or a reset.
  void replaceState(AppState next) => _persist(next.copy());

  void _persist(AppState next) {
    next.ts = DateTime.now().millisecondsSinceEpoch;
    Exercises.instance.registerCustom(next.customEx);
    final before = state;
    state = next;
    _repo.save(next);

    // The reminder schedule and the wake lock are both derived from the state rather than
    // being toggled at their call sites — so they cannot drift out of step with the plan,
    // whichever screen happened to change it.
    if (_reminderChanged(before, next)) Reminders.instance.sync(next);
    ScreenWakeLock.instance.set(next.active != null && next.keepAwake);
  }

  /// Only the parts of the state a scheduled reminder is built from.
  bool _reminderChanged(AppState a, AppState b) =>
      a.reminder.on != b.reminder.on ||
      a.reminder.time != b.reminder.time ||
      a.lang != b.lang ||
      !_sameWeek(a, b) ||
      a.routines.length != b.routines.length ||
      !_sameRoutineNames(a, b);

  bool _sameWeek(AppState a, AppState b) =>
      a.week.length == b.week.length &&
      a.week.entries.every((e) => b.week[e.key] == e.value);

  bool _sameRoutineNames(AppState a, AppState b) {
    for (var i = 0; i < a.routines.length && i < b.routines.length; i++) {
      if (a.routines[i].id != b.routines[i].id || a.routines[i].name != b.routines[i].name) {
        return false;
      }
    }
    return true;
  }

  /// A setting changed right before the app is backgrounded must not be lost mid-debounce —
  /// setting the reminder time and immediately switching away to test it is the exact case.
  Future<void> flush() => _repo.flush();
}

final appStateProvider =
    NotifierProvider<AppStateController, AppState>(AppStateController.new);

/// Reads one derived value out of the state without rebuilding on every unrelated change.
///
/// `ref.watch(appStateProvider.select((s) => s.unit))` is the idiom; this is sugar for the
/// handful of places that want it to read like the original's `useStore(s => s.S.unit)`.
extension SelectState on WidgetRef {
  T pick<T>(T Function(AppState s) selector) =>
      watch(appStateProvider.select(selector));
}

/// Keeps the file mirror honest across lifecycle changes.
class StateLifecycleObserver extends WidgetsBindingObserver {
  StateLifecycleObserver(this.ref);

  final Ref ref;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      ref.read(appStateProvider.notifier).flush();
    }
  }
}
