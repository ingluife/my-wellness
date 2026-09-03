import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Android configuration that only fails on a device.
///
/// The manifest names the launcher activity relatively (`.MainActivity`), so it resolves
/// against the Gradle `namespace`. If the two drift apart the APK builds and installs
/// perfectly and then dies at launch with ClassNotFoundException — which is exactly what
/// happened when the application id was changed and the Kotlin source was left behind.
void main() {
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

  /// The manifest with its comments stripped.
  ///
  /// Needed for any assertion about a permission being *absent*: this file explains at length
  /// why CAMERA must not be declared, and naming it in that explanation is not the same as
  /// declaring it. A bare text search cannot tell the two apart.
  final declared = manifest.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');

  String? valueOf(String key) =>
      RegExp('$key\\s*=\\s*"([^"]+)"').firstMatch(gradle)?.group(1);

  test('the launcher activity exists in the namespace the manifest resolves against', () {
    final namespace = valueOf('namespace');
    expect(namespace, isNotNull, reason: 'no namespace in build.gradle.kts');

    // `.MainActivity` is relative to the namespace; an absolute name is used as written.
    final declared =
        RegExp(r'android:name="([^"]*MainActivity)"').firstMatch(manifest)?.group(1);
    expect(declared, isNotNull, reason: 'no launcher activity in the manifest');
    final fqcn = declared!.startsWith('.') ? '$namespace$declared' : declared;

    final path = 'android/app/src/main/kotlin/${fqcn.replaceAll('.', '/')}.kt';
    expect(File(path).existsSync(), isTrue,
        reason: 'the manifest points at $fqcn, but there is no source at $path');

    // ...and the file has to declare that package, not merely sit in the right directory.
    final source = File(path).readAsStringSync();
    final pkg = RegExp(r'^package\s+([\w.]+)', multiLine: true).firstMatch(source)?.group(1);
    expect('$pkg.MainActivity', fqcn);
  });

  test('no stale sources are left in an old package', () {
    final kotlin = Directory('android/app/src/main/kotlin');
    final activities = kotlin
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('MainActivity.kt'))
        .toList();
    expect(activities, hasLength(1),
        reason: 'more than one MainActivity — a rename left a copy behind');
  });

  test('the application id and the namespace agree', () {
    // They are allowed to differ in general, but here they are meant to be the same thing,
    // and a mismatch is how the relative activity name goes wrong in the first place.
    expect(valueOf('applicationId'), valueOf('namespace'));
  });

  test('the permissions the app actually needs are declared', () {
    for (final p in const [
      'POST_NOTIFICATIONS',
      'SCHEDULE_EXACT_ALARM',
      'RECEIVE_BOOT_COMPLETED',
      'VIBRATE',
      'WAKE_LOCK',
      // Meal photos. The only reason this app touches the network at all.
      'INTERNET',
    ]) {
      expect(manifest, contains('android.permission.$p'), reason: p);
    }
  });

  test('CAMERA is not declared, and must not be', () {
    // The more valuable of the two assertions, because it encodes something nobody has otherwise:
    // image_picker takes photos through ACTION_IMAGE_CAPTURE, which needs no permission — but
    // declaring CAMERA anyway makes Android require it to be *granted* before that intent will
    // start, so the capture throws for a permission the app never prompts for. "It takes photos,
    // surely it needs CAMERA" is exactly the change this test exists to stop.
    expect(declared, isNot(contains('android.permission.CAMERA')),
        reason: 'declaring CAMERA breaks ACTION_IMAGE_CAPTURE rather than enabling it');
  });
}
