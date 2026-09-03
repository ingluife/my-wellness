import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/models/app_state.dart';
import '../domain/format.dart';

/// Getting your training log in and out of the app.
///
/// Export goes through the OS share sheet rather than a download: on a phone there is no
/// "downloads folder" worth writing to blind, and the share sheet is the one place that
/// reaches Files, mail, AirDrop and everything else at once.
class Backup {
  const Backup._();

  static String fileName() => 'mywellness-backup-${todayISO()}.json';

  /// Write [state] to a temp file and hand it to the share sheet.
  static Future<void> export(AppState state, {String? name}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${name ?? fileName()}');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(state.toJson()));
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], fileNameOverrides: [name ?? fileName()]),
    );
  }

  /// Share arbitrary JSON — used by the plan file, which is a different shape.
  static Future<void> shareJson(Object json, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
    await SharePlus.instance
        .share(ShareParams(files: [XFile(file.path)], fileNameOverrides: [name]));
  }

  /// Pick a file and read it as text. Returns null when the picker was dismissed.
  static Future<String?> pickText(List<String> extensions) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
      withData: true,
    );
    final picked = result?.files.firstOrNull;
    if (picked == null) return null;
    if (picked.bytes != null) return utf8.decode(picked.bytes!, allowMalformed: true);
    if (picked.path != null) return File(picked.path!).readAsString();
    return null;
  }

  /// Parse a backup, refusing anything that is not one.
  ///
  /// The check is deliberately shallow — `routines` and `workouts` present — because that is
  /// what makes a file a backup, and a stricter schema would reject files written by a version
  /// this build does not know about.
  static AppState parse(String raw) {
    final data = jsonDecode(raw);
    if (data is! Map<String, dynamic> ||
        !data.containsKey('workouts') ||
        !data.containsKey('routines')) {
      throw const FormatException('not a My Wellness backup');
    }
    return AppState.fromJson(data);
  }
}
