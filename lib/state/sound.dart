import 'package:audioplayers/audioplayers.dart';
import 'package:vibration/vibration.dart';

/// The app's beeps and haptics.
///
/// The original synthesises these with WebAudio; the same six tones are pre-rendered with the
/// same gain envelope (see tool/gen_tones.mjs) and played from assets, which keeps the timing
/// exact and costs nothing at runtime. `enabled` gates sound only — haptics are a separate
/// channel and stay on, because they are what you feel through a pocket mid-set.
class Sound {
  Sound();

  final _players = <String, AudioPlayer>{};

  Future<void> _play(bool enabled, String tone, {Duration delay = Duration.zero}) async {
    if (!enabled) return;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    try {
      final p = _players.putIfAbsent(tone, () => AudioPlayer()..setReleaseMode(ReleaseMode.stop));
      await p.stop();
      await p.play(AssetSource('audio/$tone.wav'), volume: 1);
    } catch (_) {
      // No audio route, or the platform refused — never worth interrupting a workout over.
    }
  }

  Future<void> _vibrate(List<int> pattern) async {
    try {
      if (await Vibration.hasVibrator()) {
        await Vibration.vibrate(pattern: [0, ...pattern]);
      }
    } catch (_) {/* not every device has one */}
  }

  /// The last three seconds of a countdown.
  void countdown(bool enabled) => _play(enabled, '660_100');

  /// A set checked off.
  void setDone(bool enabled) {
    _play(enabled, '1040_120');
    _vibrate([30]);
  }

  /// The rest timer, or a timed hold, reaching zero.
  void restOver(bool enabled) {
    _play(enabled, '880_150');
    _play(enabled, '880_150', delay: const Duration(milliseconds: 250));
    _play(enabled, '1320_400', delay: const Duration(milliseconds: 500));
    _vibrate([200, 100, 200]);
  }

  /// The workout finished — a rising three-note figure.
  void workoutDone(bool enabled) {
    _play(enabled, '880_150');
    _play(enabled, '1100_150', delay: const Duration(milliseconds: 180));
    _play(enabled, '1320_300', delay: const Duration(milliseconds: 360));
  }

  /// A bare acknowledgement, no tone.
  void tap() => _vibrate([30]);

  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
  }
}
