import 'package:flutter/services.dart';

import '../data/models/app_state.dart';
import '../domain/exercises.dart';
import '../domain/format.dart';
import '../domain/history.dart';
import '../domain/i18n.dart';
import '../domain/set_columns.dart';
import '../state/active_session.dart';
import '../state/ui_provider.dart';

/// Every string and flag the ongoing notification paints, derived from the session.
///
/// A record rather than a class: it has structural equality for free, which is what lets
/// [WorkoutNotification.sync] skip the platform channel on a state change that does not move
/// anything the notification shows — a meal logged mid-workout, say.
typedef WorkoutNotif = ({
  String title,
  String body,
  String sub,
  String minusLabel,
  String plusLabel,
  String doneLabel,
  bool canSwap,
  int? restEndsAt,
});

/// Derives the notification from the session, or null when there is nothing to show.
///
/// Pure and platform-free on purpose, so it can be asserted against directly — see
/// test/workout_notification_test.dart — without a `MethodChannel` in earshot. [swap] picks the
/// entry's second column over its first — which, in `setColumnsFor` order, means weight over
/// reps for an ordinary lift, the same priority the workout screen's own steppers show. Where
/// there is no second column (a bodyweight set with nothing added, a cardio duration alone),
/// the flag is simply ignored and [WorkoutNotif.canSwap] comes back false, so the "tap to
/// switch" tap has nothing to switch.
WorkoutNotif? render(AppState s, ActiveSession session, {required bool swap, CountDown? rest}) {
  final a = s.active;
  if (a == null) return null;

  final focus = session.focus(s);
  if (focus == null) {
    // Every set in the session is logged, but it has not been finished from the app yet.
    return (
      title: a.name,
      body: t('All sets logged'),
      sub: t('Open the app to finish the workout'),
      minusLabel: '',
      plusLabel: '',
      doneLabel: '',
      canSwap: false,
      restEndsAt: rest?.endsAt,
    );
  }

  final entry = a.entries[focus.entry];
  final ex = exdb.or(entry.id);
  final set = entry.sets[focus.set];
  final cols = setColumnsFor(s, entry);
  final canSwap = cols.col2 != null;
  final col = swap && canSwap ? cols.col2! : cols.col1;
  final other = swap && canSwap ? cols.col1 : cols.col2;

  return (
    title: '${_cap(ex.n)} · ${t('Set {0}/{1}', focus.set + 1, entry.sets.length)}',
    body: setLabel(entry.id, set, entry.cfg),
    sub: canSwap ? t('Adjusting {0} · tap to switch to {1}', col.heading, other!.heading) : '',
    minusLabel: '−${fmtNum(col.step)}',
    plusLabel: '+${fmtNum(col.step)}',
    doneLabel: t('✓ Set'),
    canSwap: canSwap,
    restEndsAt: rest?.endsAt,
  );
}

/// CSS `text-transform: capitalize`, ported locally rather than importing the UI widgets file
/// this platform singleton has no other reason to depend on — see
/// lib/ui/widgets/controls/surfaces.dart for the original.
String _cap(String s) => s.isEmpty
    ? s
    : s.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');

/// The ongoing, quick-action notification for an active workout.
///
/// Follows the shape of [lib/platform/reminders.dart]: a singleton, swallows every platform
/// failure, and is a no-op on anything but Android. Unlike the reminder, this one is driven by
/// [sync] being called on *every* write to [AppState] — see `AppStateController._persist` —
/// rather than by its own call sites, so it cannot drift out of step with the session whether
/// the write came from the app or from the notification's own buttons.
class WorkoutNotification {
  WorkoutNotification._();

  static final WorkoutNotification instance = WorkoutNotification._();

  static const _channel = MethodChannel('com.mywellness.app/workout_notification');

  ActiveSession? _session;
  UiController? _ui;
  AppState Function()? _read;
  bool _bound = false;

  /// The entry's second column over its first — see the doc on [render]'s `swap` parameter,
  /// which this feeds. Presentation state, not session state: it lives here rather than on
  /// [AppState] because it means nothing once the notification is gone.
  bool _swap = false;

  WorkoutNotif? _last;

  /// Wires the singleton to the app's one [ActiveSession] and [UiController], and starts
  /// listening for actions from the notification's buttons. Called once, from the app's
  /// `initState` — see lib/ui/app.dart.
  void bind(ActiveSession session, UiController ui, AppState Function() read) {
    _session = session;
    _read = read;
    if (!_bound || _ui != ui) {
      _ui?.removeListener(_onUiChanged);
      _ui = ui;
      _ui!.addListener(_onUiChanged);
    }
    _bound = true;
    _channel.setMethodCallHandler(_onAction);
  }

  /// The rest countdown ticks on its own timer, outside any `AppState` write — see the doc on
  /// [UiController]. Redrawing here is what keeps the notification's rest cue live when it was
  /// started, skipped or extended from the in-app timer bar rather than from a set toggled here.
  void _onUiChanged() {
    final read = _read;
    if (read != null) sync(read());
  }

  Future<dynamic> _onAction(MethodCall call) async {
    final session = _session;
    final read = _read;
    if (session == null || read == null) return null;

    switch (call.method) {
      case 'minus':
      case 'plus':
        final focus = session.focus(read());
        if (focus == null) break;
        final entry = read().active!.entries[focus.entry];
        final cols = setColumnsFor(read(), entry);
        final col = _swap && cols.col2 != null ? cols.col2! : cols.col1;
        final sign = call.method == 'minus' ? -1.0 : 1.0;
        session.adjust(focus.entry, focus.set, col.field, sign * col.step);
      case 'done':
        final focus = session.focus(read());
        if (focus != null) session.toggle(focus.entry, focus.set);
      case 'swap':
        _swap = !_swap;
        await sync(read());
    }
    return null;
  }

  /// Redraws the notification, or cancels it and stops the service once there is nothing left
  /// to show. Safe — and cheap — to call on every state write: a model that renders identical
  /// to the last one never reaches the channel.
  Future<void> sync(AppState s) async {
    if (!s.workoutNotif || s.active == null) {
      if (_last != null) {
        _last = null;
        await _send('cancel', null);
      }
      return;
    }
    final session = _session;
    // Not bound yet — a state write that lands before the app's first frame. It replays once
    // `bind` runs, because that call ends with a `sync` of its own.
    if (session == null) return;

    final model = render(s, session, swap: _swap, rest: _ui?.rest);
    if (model == _last) return;
    _last = model;
    if (model == null) {
      await _send('cancel', null);
    } else {
      await _send('show', {
        'title': model.title,
        'body': model.body,
        'sub': model.sub,
        'minusLabel': model.minusLabel,
        'plusLabel': model.plusLabel,
        'doneLabel': model.doneLabel,
        'canSwap': model.canSwap,
        'restEndsAt': model.restEndsAt,
      });
    }
  }

  Future<void> _send(String method, Object? args) async {
    try {
      await _channel.invokeMethod(method, args);
    } catch (_) {
      // No native side (iOS, a test host, a channel that failed to attach) — never worth
      // interrupting a workout over. The next `sync` tries again.
    }
  }
}
