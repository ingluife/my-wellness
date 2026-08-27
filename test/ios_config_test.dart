import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// iOS configuration that only fails on a device, and late.
///
/// A missing usage-description string does not fail the build. The app installs, runs, and then
/// crashes at the instant the user taps "Take a photo" — the one moment they were trusting it
/// with something. Follows the precedent of android_config_test.dart: read the file as text and
/// assert what has to be in it.
void main() {
  final plist = File('ios/Runner/Info.plist').readAsStringSync();

  /// The plist with its comments stripped.
  ///
  /// Needed for any assertion about a key being *absent*, because the file explains in a comment
  /// which permissions are deliberately not requested — and naming one there is not declaring it.
  /// Exactly the same trap as android_config_test.dart's CAMERA check.
  final declared = plist.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  test('the camera and library usage strings are declared', () {
    for (final key in const ['NSCameraUsageDescription', 'NSPhotoLibraryUsageDescription']) {
      expect(plist, contains('<key>$key</key>'), reason: key);
    }
  });

  test('each usage string actually says something', () {
    // An empty string satisfies the linker and gets the app rejected at review — and tells the
    // user nothing about why an app that tracks squats wants their camera.
    for (final key in const ['NSCameraUsageDescription', 'NSPhotoLibraryUsageDescription']) {
      final value = RegExp('<key>$key</key>\\s*<string>([^<]*)</string>').firstMatch(plist);
      expect(value, isNotNull, reason: '$key has no string value');
      expect(value!.group(1)!.trim().length, greaterThan(10), reason: key);
    }
  });

  test('no permission is requested that the app has no use for', () {
    // Stills only. Asking for the microphone would be requesting access to a sensor the feature
    // never reads, which is both a review risk and a broken promise.
    expect(declared, isNot(contains('NSMicrophoneUsageDescription')));
    expect(declared, isNot(contains('NSLocationWhenInUseUsageDescription')));
    expect(declared, isNot(contains('NSContactsUsageDescription')));
  });
}
