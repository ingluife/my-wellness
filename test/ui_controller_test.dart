import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_open_gym/state/sound.dart';
import 'package:my_open_gym/state/ui_provider.dart';

/// A sound service that records what it was asked to play instead of touching an audio route.
class _FakeSound implements Sound {
  final calls = <String>[];

  @override
  void countdown(bool enabled) => calls.add('countdown');
  @override
  void setDone(bool enabled) => calls.add('setDone');
  @override
  void restOver(bool enabled) => calls.add('restOver');
  @override
  void workoutDone(bool enabled) => calls.add('workoutDone');
  @override
  void tap() => calls.add('tap');
  @override
  void dispose() {}
  @override
  noSuchMethod(Invocation i) => null;
}

void main() {
  /// A controller whose clock is the fake one, so `elapse` moves the countdown as well as
  /// the timers driving it.
  UiController controller(FakeAsync async, _FakeSound snd) {
    const base = 1700000000000;
    return UiController(sound: snd, now: () => base + async.elapsed.inMilliseconds);
  }

  test('a rest countdown ticks down and announces the end once', () {
    fakeAsync((async) {
      final snd = _FakeSound();
      final ui = controller(async, snd);
      ui.startRest(5, soundOn: true);
      expect(ui.rest!.left, 5);
      expect(ui.rest!.clock, '0:05');

      async.elapse(const Duration(seconds: 2));
      expect(ui.rest!.left, 3);
      // Only the last three seconds get the countdown blip.
      expect(snd.calls, ['countdown']);

      async.elapse(const Duration(seconds: 3));
      expect(ui.rest, isNull, reason: 'the timer clears itself at zero');
      expect(snd.calls.last, 'restOver');
      expect(ui.toastMessage, contains('Rest over'));
    });
  });

  test('adding time extends the bar as well as the clock', () {
    fakeAsync((async) {
      final ui = controller(async, _FakeSound());
      ui.startRest(60, soundOn: false);
      ui.addRest(15);
      expect(ui.rest!.left, 75);
      expect(ui.rest!.total, 75);
    });
  });

  test('taking off more time than is left is the same as skipping', () {
    fakeAsync((async) {
      final ui = controller(async, _FakeSound());
      ui.startRest(10, soundOn: false);
      ui.addRest(-15);
      // Not a negative countdown, and not a bar running backwards.
      expect(ui.rest, isNull);
    });
  });

  test('the countdown is read off the wall clock, so a backgrounded app catches up', () {
    fakeAsync((async) {
      final ui = controller(async, _FakeSound());
      ui.startRest(90, soundOn: false);
      // No ticks are delivered while suspended, but 30s of wall time still passed.
      async.elapse(const Duration(seconds: 30));
      expect(ui.rest!.left, 60);
    });
  });

  test('starting a work timer stops any rest — the two mean opposite things', () {
    fakeAsync((async) {
      final ui = controller(async, _FakeSound());
      ui.startRest(90, soundOn: false);
      ui.startWork(45, 'plank', (_) {}, soundOn: false);
      expect(ui.rest, isNull);
      expect(ui.work!.total, 45);
      expect(ui.work!.label, 'plank');
      expect(ui.timer, same(ui.work));
    });
  });

  test('a hold that runs out logs the full target', () {
    fakeAsync((async) {
      double? logged;
      final ui = controller(async, _FakeSound());
      ui.startWork(45, 'plank', (e) => logged = e, soundOn: false);
      async.elapse(const Duration(seconds: 45));
      expect(logged, 45);
      expect(ui.work, isNull);
    });
  });

  test('finishing early logs what was actually held, not the target', () {
    fakeAsync((async) {
      double? logged;
      final ui = controller(async, _FakeSound());
      ui.startWork(45, 'plank', (e) => logged = e, soundOn: false);
      async.elapse(const Duration(seconds: 38));
      ui.finishWorkEarly();
      // 0:38 of a 0:45 hold records 0:38.
      expect(logged, 38);
      expect(ui.work, isNull);
    });
  });

  test('abandoning a hold logs nothing at all', () {
    fakeAsync((async) {
      var called = false;
      final ui = controller(async, _FakeSound());
      ui.startWork(45, 'plank', (_) => called = true, soundOn: false);
      async.elapse(const Duration(seconds: 20));
      ui.stopWork();
      expect(called, isFalse);
      expect(ui.work, isNull);
    });
  });

  test('a toast clears itself', () {
    fakeAsync((async) {
      final ui = controller(async, _FakeSound());
      ui.toast('Weight saved');
      expect(ui.toastMessage, 'Weight saved');
      async.elapse(const Duration(milliseconds: 2200));
      expect(ui.toastMessage, isEmpty);
    });
  });
}
