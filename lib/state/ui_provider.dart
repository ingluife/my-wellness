import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/format.dart';
import '../domain/i18n.dart';
import 'sound.dart';

/// Ephemeral UI state — the half of the app that is not the training log.
///
/// Ported from `useUI`: a toast, and the two countdowns. Kept apart from the persisted state
/// on purpose, because none of it should survive a restart and none of it belongs in a backup.
///
/// The sheet stack is *not* here: Flutter's navigator already is a stack of routes with the
/// dismissal, back-button and focus behaviour a sheet needs, so sheets are pushed onto it (see
/// ui/sheets/sheet_service.dart) rather than reimplemented as a list of render callbacks.
class UiController extends ChangeNotifier {
  UiController({Sound? sound, int Function()? now})
      : _sound = sound ?? Sound(),
        _now = now ?? _wallClock;

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  final Sound _sound;

  /// The clock the countdowns read. Injectable so a test can drive time forward without
  /// waiting out a real ninety-second rest.
  final int Function() _now;

  String _toast = '';
  Timer? _toastTimer;

  /// The rest countdown between sets.
  CountDown? _rest;

  /// The work countdown *during* a timed set.
  CountDown? _work;

  Timer? _restTicker;
  Timer? _workTicker;
  void Function(double elapsedSec)? _workDone;

  String get toastMessage => _toast;
  CountDown? get rest => _rest;
  CountDown? get work => _work;

  /// Whichever countdown is running — they are mutually exclusive by construction.
  CountDown? get timer => _work ?? _rest;

  /// The rising three-note figure that closes a session.
  void workoutDone(bool soundOn) => _sound.workoutDone(soundOn);

  /// A set checked off.
  void setDone(bool soundOn) => _sound.setDone(soundOn);

  void toast(String message) {
    _toast = message;
    notifyListeners();
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 2200), () {
      _toast = '';
      notifyListeners();
    });
  }

  /* ------------------------------------------------------------------ rest -- */

  void startRest(double seconds, {required bool soundOn}) {
    stopRest();
    final total = seconds.round();
    _rest = CountDown(
      left: total,
      total: total,
      endsAt: _now() + total * 1000,
    );
    notifyListeners();
    _restTicker = Timer.periodic(const Duration(seconds: 1), (_) => _tickRest(soundOn));
  }

  void _tickRest(bool soundOn) {
    final tm = _rest;
    if (tm == null) return;
    final left = _leftOf(tm);
    if (left == tm.left) return;
    if (left <= 0) {
      _sound.restOver(soundOn);
      toast(t('Rest over — next set!'));
      stopRest();
      return;
    }
    if (left <= 3) _sound.countdown(soundOn);
    _rest = tm.copyWith(left: left);
    notifyListeners();
  }

  /// Take time off or add it. Removing more than is left means "I'm ready now" — the same as
  /// skipping, and it keeps a negative duration out of the progress bar.
  void addRest(int seconds) {
    final tm = _rest;
    if (tm == null) return;
    final left = tm.left + seconds;
    if (left <= 0) {
      stopRest();
      return;
    }
    _rest = CountDown(left: left, total: tm.total + seconds, endsAt: tm.endsAt + seconds * 1000);
    notifyListeners();
  }

  void stopRest() {
    _restTicker?.cancel();
    _restTicker = null;
    if (_rest != null) {
      _rest = null;
      notifyListeners();
    }
  }

  /* ------------------------------------------------------------------ work -- */

  /// Times the set itself, not the recovery after it.
  ///
  /// Kept separate from the rest timer on purpose: the two mean opposite things, they must
  /// never run together, and a work set is something you are watching. [onDone] is called both
  /// when the countdown reaches zero and on an early finish; the elapsed time is what gets
  /// logged, so stopping at 0:38 of a 0:45 hold records 0:38 rather than crediting the target.
  void startWork(double seconds, String label, void Function(double elapsed) onDone,
      {required bool soundOn}) {
    stopWork();
    stopRest();
    final total = seconds.round().clamp(1, 1 << 30);
    _workDone = onDone;
    _work = CountDown(
      left: total,
      total: total,
      endsAt: _now() + total * 1000,
      label: label,
    );
    notifyListeners();
    _workTicker = Timer.periodic(const Duration(seconds: 1), (_) => _tickWork(soundOn));
  }

  void _tickWork(bool soundOn) {
    final wk = _work;
    if (wk == null) return;
    final left = _leftOf(wk);
    if (left == wk.left) return;
    if (left <= 0) {
      _sound.restOver(soundOn);
      final done = _workDone;
      final total = wk.total;
      stopWork();
      done?.call(total.toDouble());
      return;
    }
    if (left <= 3) _sound.countdown(soundOn);
    _work = wk.copyWith(left: left);
    notifyListeners();
  }

  /// Ended the hold early — log what was actually held.
  void finishWorkEarly() {
    final wk = _work;
    if (wk == null) return;
    final elapsed = (wk.total - wk.left).clamp(1, wk.total);
    final done = _workDone;
    _sound.tap();
    stopWork();
    done?.call(elapsed.toDouble());
  }

  /// Abandon without logging anything.
  void stopWork() {
    _workTicker?.cancel();
    _workTicker = null;
    _workDone = null;
    if (_work != null) {
      _work = null;
      notifyListeners();
    }
  }

  /// Read off the wall clock, not off a tick count: a timer that missed ticks while the app
  /// was backgrounded must come back showing the right number, not a stale one.
  int _leftOf(CountDown c) =>
      (((c.endsAt - _now()) / 1000).round()).clamp(0, 1 << 30);

  /// Called when the app returns to the foreground, so a countdown catches up at once instead
  /// of on its next tick.
  void resync({required bool soundOn}) {
    if (_rest != null) _tickRest(soundOn);
    if (_work != null) _tickWork(soundOn);
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _restTicker?.cancel();
    _workTicker?.cancel();
    super.dispose();
  }
}

/// A running countdown.
@immutable
class CountDown {
  const CountDown({required this.left, required this.total, required this.endsAt, this.label});

  final int left;
  final int total;
  final int endsAt;

  /// The exercise being held, shown by the work timer.
  final String? label;

  double get progress => total == 0 ? 0 : (left / total).clamp(0, 1);

  String get clock => '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}';

  CountDown copyWith({int? left}) =>
      CountDown(left: left ?? this.left, total: total, endsAt: endsAt, label: label);
}

/// `uid()` lives in format.dart; re-exported here so callers that only need an id for a
/// transient UI object do not have to reach into the domain layer.
String uiId() => uid();
