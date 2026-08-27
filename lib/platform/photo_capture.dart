import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import '../domain/ai/jpeg_scrub.dart';

/// Getting a photograph of a meal off the camera or out of the library.
///
/// A seam rather than a direct call, for the same reason `AiKeyStore` is one: the review sheet is
/// worth testing end to end, and a widget test cannot open a camera. [MemoryPhotoCapture] is the
/// double, and lives here so the contract and its fake cannot drift apart.
abstract interface class PhotoCapture {
  /// The photograph, downscaled and scrubbed, or null if the user backed out.
  Future<Uint8List?> pick({required bool fromCamera});
}

/// How large a photograph is allowed to be by the time it goes on the wire.
///
/// At roughly 1024x768 and quality 80 a food photo lands around 100–180 KB, and base64 inflates
/// that by a third. This ceiling is far above anything that bounding box produces — it is a guard
/// against something having gone wrong upstream, not a routine step.
///
/// There is deliberately no "too big, re-encode harder" path. Re-encoding without the `image`
/// package means a second trip through the picker, which means a second prompt at the user for a
/// problem they did not cause; and pulling in a full pure-Dart JPEG codec to handle a case the
/// bounding box already prevents is a lot of machinery for nothing.
const _refuseAbove = 1500 * 1024;

class ImagePickerCapture implements PhotoCapture {
  ImagePickerCapture({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick({required bool fromCamera}) async {
    final file = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      // These three are not only about size. Passing any of them makes the plugin re-encode, and
      // the re-encoded output does not carry the original EXIF — so they are also the first half
      // of the privacy story, with stripJpegMetadata as the second. Calling pickImage bare would
      // hand back the camera's own file, GPS and all.
      //
      // A bounding box, not a target: a 4032x3024 photo comes back 1024x768, so the long edge
      // lands on 1024. That is what the providers want anyway — Anthropic downsizes anything much
      // larger before it looks at it, so sending more is paying to have pixels thrown away.
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 80,
    );
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    if (bytes.length > _refuseAbove) return null;

    return stripJpegMetadata(bytes);
  }
}

/// The double the widget tests inject: fixture bytes, no platform channel, no camera.
class MemoryPhotoCapture implements PhotoCapture {
  MemoryPhotoCapture(this.bytes);

  /// Null stands for the user cancelling the picker.
  final Uint8List? bytes;

  /// What the sheet asked for last, so a test can assert the camera button opened the camera.
  bool? lastFromCamera;

  @override
  Future<Uint8List?> pick({required bool fromCamera}) async {
    lastFromCamera = fromCamera;
    return bytes;
  }
}
