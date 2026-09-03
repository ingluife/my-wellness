import 'dart:typed_data';

/// Strips the metadata segments a camera writes into a JPEG, before it is sent anywhere.
///
/// This is belt and braces, and deliberately so. `image_picker` re-encodes whenever any of
/// `maxWidth` / `maxHeight` / `imageQuality` is set — which the capture path always does — and the
/// re-encoded output does not carry the original EXIF. So in normal operation there is nothing
/// here to remove.
///
/// It exists anyway because the thing being defended against is severe and silent. A phone camera
/// writes GPS coordinates into EXIF by default; this app's whole promise is that nothing leaves
/// the phone; and "a meal photo quietly carried the user's home address to a third party" is the
/// worst bug this feature could possibly have. That the plugin *probably* prevents it, across two
/// platforms and however many future versions, is not the standard that claim deserves. Forty
/// lines and a test are cheaper than being wrong once.
///
/// Pure, over bytes, no dependency. Adding the `image` package — a full pure-Dart decoder — to do
/// this would be an enormous amount of machinery for a job that is a walk over segment markers.

/// Segments dropped, by marker byte:
///
/// - `APP1` (0xE1) — EXIF, and XMP. This is the one that carries GPS, the capture timestamp, the
///   device serial and the lens.
/// - `APP13` (0xED) — Photoshop image resource blocks, which is where IPTC lands.
/// - `COM` (0xFE) — a free-text comment field; whatever a previous tool decided to put there.
///
/// Everything else is passed through untouched, including `APP2` (ICC colour profiles), which is
/// about how the image renders rather than about who took it.
const _strip = {0xE1, 0xED, 0xFE};

/// Markers that stand alone — no length, no payload.
///
/// `RST0`–`RST7` (0xD0–0xD7) and `TEM` (0x01). Reading a length after one of these would consume
/// two bytes of the next segment and desynchronise the whole walk.
bool _isStandalone(int marker) => (marker >= 0xD0 && marker <= 0xD7) || marker == 0x01;

/// [jpeg] without its identifying metadata, or [jpeg] unchanged if it cannot be parsed.
///
/// Never throws and never returns something that is not a valid JPEG. On anything unexpected the
/// original bytes come back: a photograph that still has its EXIF is a privacy problem, but a
/// corrupted one the provider rejects is a broken feature, and quietly mangling a file is worse
/// than declining to touch it. The caller can still decline to send.
Uint8List stripJpegMetadata(Uint8List jpeg) {
  // SOI. Anything not starting FFD8 is not a JPEG and is not this function's business.
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return jpeg;

  final out = BytesBuilder()..add([0xFF, 0xD8]);
  var i = 2;

  while (i < jpeg.length) {
    // Segments are FF <marker>. Fill bytes of FF are legal between segments.
    if (jpeg[i] != 0xFF) return jpeg;
    var j = i;
    while (j < jpeg.length && jpeg[j] == 0xFF) {
      j++;
    }
    if (j >= jpeg.length) return jpeg;

    final marker = jpeg[j];

    // SOS: everything after this is entropy-coded scan data, with no segment structure to walk.
    // Copy the remainder verbatim and stop — parsing on past here is how a scrubber corrupts an
    // image, because scan data contains bytes that look exactly like markers.
    if (marker == 0xDA) {
      out.add(jpeg.sublist(i));
      return out.toBytes();
    }

    if (marker == 0xD9) {
      out.add(jpeg.sublist(i));
      return out.toBytes();
    }

    if (_isStandalone(marker)) {
      out.add(jpeg.sublist(i, j + 1));
      i = j + 1;
      continue;
    }

    // Length is big-endian and counts itself, so it is always at least 2.
    if (j + 2 >= jpeg.length) return jpeg;
    final length = (jpeg[j + 1] << 8) | jpeg[j + 2];
    if (length < 2) return jpeg;

    final end = j + 1 + length;
    if (end > jpeg.length) return jpeg;

    if (!_strip.contains(marker)) out.add(jpeg.sublist(i, end));
    i = end;
  }

  return out.toBytes();
}
