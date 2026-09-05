import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/app_state.dart';
import '../data/repositories/meal_photo_store.dart';
import '../data/repositories/state_repository.dart';
import '../domain/exercises.dart';
import '../domain/foods.dart';
import '../domain/format.dart';
import '../domain/i18n.dart';
import '../platform/reminders.dart';
import '../platform/wake_lock.dart';
import '../platform/workout_notification.dart';

final stateRepositoryProvider = Provider<StateRepository>((ref) {
  final repo = StateRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Where meal photographs are kept. Beside the state repository rather than with the AI wiring,
/// because it is storage the app owns and outlives any provider the photo was read by: a user who
/// removes their API key still has the pictures of what they ate.
final mealPhotoStoreProvider = Provider<MealPhotoStore>((ref) => FileMealPhotoStore());

/// One meal's photograph, by file name.
///
/// A family so the framework caches it: a day of meals rebuilds on every keystroke of a stepper,
/// and re-reading the same JPEGs off disk each time would be a scroll's worth of I/O for an image
/// that has not changed. Null is the ordinary answer, not an error — see [Meal.photo].
final mealPhotoProvider = FutureProvider.family<Uint8List?, String>(
  (ref, name) => ref.watch(mealPhotoStoreProvider).read(name),
);

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
    Foods.instance.registerCustom(s.nutrition.foods);
    await I18n.instance.setLang(s.lang);

    // Re-stamp the reminder's timezone on every launch — keeps it correct if you are
    // travelling, without needing to revisit Settings.
    final tz = localTZ();
    if (s.reminder.on && s.reminder.tz != tz) s.reminder.tz = tz;

    state = s;
    if (s.reminder.on) Reminders.instance.sync(s);
    ScreenWakeLock.instance.set(s.active != null && s.keepAwake);

    // Housekeeping, and unawaited on purpose: deleting last quarter's photographs is never worth
    // a frame of the first screen the user sees.
    unawaited(sweepPhotos());
  }

  /// Drops the meal photographs the log no longer refers to, and the references to files that are
  /// no longer there.
  ///
  /// Run at boot, and again the moment the setting is switched off — the same call, because
  /// "keep none" is only a keep set with nothing in it. See [sweepMealPhotos].
  Future<void> sweepPhotos() async {
    final keep = state.ai.features[aiMealPhoto]?.keepsPhotos ?? true;
    final drop = await sweepMealPhotos(ref.read(mealPhotoStoreProvider), state.meals,
        keepPhotos: keep);
    if (drop.isEmpty) return;
    update((st) {
      for (final m in st.meals) {
        if (m.photo != null && drop.contains(m.photo)) m.photo = null;
      }
    });
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
    Foods.instance.registerCustom(next.nutrition.foods);
    final before = state;
    state = next;
    _repo.save(next);

    // The reminder schedule and the wake lock are both derived from the state rather than
    // being toggled at their call sites — so they cannot drift out of step with the plan,
    // whichever screen happened to change it.
    if (_reminderChanged(before, next)) Reminders.instance.sync(next);
    ScreenWakeLock.instance.set(next.active != null && next.keepAwake);
    // Runs on every write, not just the ones that change a set — it is what keeps the
    // notification from ever disagreeing with the state, whichever side changed it. See the
    // doc on WorkoutNotification for why that matters more here than for the reminder above.
    unawaited(WorkoutNotification.instance.sync(next));
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
