import '../data/models/app_state.dart';
import '../domain/history.dart';
import 'ui_provider.dart';

/// What marking a set implies. The mutation is already done; this is what the caller — one
/// that *can* show a sheet or a toast — should do about it, if anything.
typedef SetToggled = ({
  int entryIndex,
  bool askTopWeight,
  bool exerciseDone,
  bool workoutDone,
  String mode,
});

/// Mutates the active session and reports the follow-up as data instead of acting on it.
///
/// `_SetRow._toggle` used to be both the mutation and the dispatch — flip `done`, then decide
/// whether to open the top-weight sheet, the finish sheet, or a toast. Splitting the two is what
/// lets the same mutation run from the quick-action notification, which can redraw itself but
/// cannot open a Flutter sheet.
///
/// Takes the read/update pair rather than a `Ref`, so it works the same from a `WidgetRef` (the
/// workout screen) and from a plain `Ref` (the notification's provider) without caring which.
class ActiveSession {
  ActiveSession({
    required AppState Function() read,
    required void Function(void Function(AppState s) mutate) update,
    required UiController ui,
  })  : _read = read,
        _update = update,
        _ui = ui;

  final AppState Function() _read;
  final void Function(void Function(AppState s) mutate) _update;
  final UiController _ui;

  /// The set the quick-action controls act on: the first unmarked set of the first entry with
  /// work left, scanning forward from `active.cur` and wrapping around. Null once every set in
  /// the session is done, or there is no session.
  ({int entry, int set})? focus(AppState s) {
    final a = s.active;
    if (a == null || a.entries.isEmpty) return null;
    final n = a.entries.length;
    final start = a.cur.clamp(0, n - 1);
    for (var i = 0; i < n; i++) {
      final idx = (start + i) % n;
      final setIdx = a.entries[idx].sets.indexWhere((x) => !x.done);
      if (setIdx != -1) return (entry: idx, set: setIdx);
    }
    return null;
  }

  /// Adds [delta] to one column of a set, floored at 0 — a quick-action tap, as opposed to the
  /// absolute value a stepper writes directly through [SetLog.setField].
  void adjust(int entryIndex, int setIndex, String field, double delta) {
    _update((st) {
      final set = st.active!.entries[entryIndex].sets[setIndex];
      final next = (set.field(field) ?? 0) + delta;
      set.setField(field, next < 0 ? 0 : next);
    });
  }

  /// The body of the old `_SetRow._toggle`, minus the sheet dispatch — see [SetToggled]. Null
  /// only when there is no active session to act on.
  SetToggled? toggle(int entryIndex, int setIndex) {
    final s = _read();
    final a = s.active;
    if (a == null) return null;

    final units = supersetUnits(a.entries);
    final unit = unitOf(units, entryIndex);
    final unitIdx = units.indexWhere((u) => u.contains(entryIndex));
    final isLastUnit = unitIdx >= units.length - 1;
    final entry = a.entries[entryIndex];
    final mode = modeOf(entry.cfg);

    var askTop = false;
    var exJustDone = false;
    var workoutDone = false;

    _update((st) {
      final e = st.active!.entries[entryIndex];
      final set = e.sets[setIndex];
      set.done = !set.done;
      if (!set.done) return;

      _ui.setDone(st.sound);
      final isLastExInUnit = entryIndex == unit.last;
      final unitDone =
          unit.every((ui) => st.active!.entries[ui].sets.every((x) => x.done));
      if (isLastExInUnit && !unitDone) {
        _ui.startRest(st.restSec, soundOn: st.sound);
      } else if (unitDone) {
        _ui.stopRest();
      }
      if (unitDone && isLastUnit) workoutDone = true;

      // Only loaded reps training has a "working weight" worth confirming — a bodyweight plank
      // has nothing to put in that slider, and neither does a set of push-ups.
      final loaded =
          mode == 'reps' && !(isBw(e.cfg) && !e.sets.any((x) => (x.w ?? 0) > 0));
      if (e.sets.every((x) => x.done)) {
        exJustDone = true;
        if (loaded && !e.asked) {
          e.asked = true;
          askTop = true;
        }
      }
    });

    return (
      entryIndex: entryIndex,
      askTopWeight: askTop,
      exerciseDone: exJustDone,
      workoutDone: workoutDone,
      mode: mode,
    );
  }
}
