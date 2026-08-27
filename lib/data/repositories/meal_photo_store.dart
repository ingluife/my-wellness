import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../domain/format.dart';
import '../models/nutrition.dart';

/// Where a photographed meal's photograph lives.
///
/// Not in the state. A JPEG is ~150 KB and `AppState` is re-serialised on every keystroke of a
/// stepper, written to preferences, mirrored to a plaintext file and copied into every backup the
/// user shares — putting images in there would inflate all four by two orders of magnitude for
/// something nothing computes from. So the state carries a file name and the bytes sit in their own
/// directory, which also means **a backup does not carry photos**. That is a real limitation and
/// the settings screen says so rather than letting the user find out on a new phone.
///
/// Nothing here ever throws. A photograph is decoration on a record that is already complete: if
/// the disk is full, or the directory cannot be created, or the file has been deleted by something
/// else, the meal is still logged and the day still adds up. Failing a log because a picture would
/// not write would be the tail wagging the dog.
abstract interface class MealPhotoStore {
  /// Writes [jpeg] and returns its file name, or null if it could not be stored.
  Future<String?> save(Uint8List jpeg);

  /// The bytes behind [name], or null if there is nothing there any more.
  Future<Uint8List?> read(String name);

  Future<void> delete(String name);

  /// Deletes every stored photo whose name is not in [keep], and returns the names that are still
  /// on disk afterwards — or **null** if the directory could not be read.
  ///
  /// The null is not tidiness. Callers drop the state's references to whatever this does not
  /// return, so an unreadable directory reported as "nothing survives" would erase every reference
  /// in the log over a transient I/O error. Not knowing has to be distinguishable from knowing the
  /// answer is empty.
  Future<Set<String>?> sweep(Set<String> keep);

  /// Everything this store holds. For a reset.
  Future<void> clear();
}

/// How long a photograph is kept.
///
/// Long enough to look back over a season of eating, short enough that the app's footprint stops
/// growing: at four photographed meals a day this bounds the directory at roughly 50 MB rather
/// than at "forever". A user who wants none keeps none — see `AiFeatureConfig.keepPhotos`.
const mealPhotoRetention = Duration(days: 90);

/// Photos in a directory of their own inside the app's private documents area.
class FileMealPhotoStore implements MealPhotoStore {
  FileMealPhotoStore({Directory? dir}) : _root = dir;

  static const dirName = 'meal_photos';

  Directory? _root;
  Directory? _dir;

  Future<Directory?> _open() async {
    if (_dir != null) return _dir;
    try {
      _root ??= await getApplicationDocumentsDirectory();
      final d = Directory('${_root!.path}/$dirName');
      if (!d.existsSync()) await d.create(recursive: true);
      return _dir = d;
    } catch (_) {
      // No documents directory (a test binding with no platform channels), or a read-only disk.
      return null;
    }
  }

  @override
  Future<String?> save(Uint8List jpeg) async {
    final dir = await _open();
    if (dir == null) return null;
    // The same id shape every other record in the app uses, so a photo file sorts and reads like
    // the `ml…` meal it belongs to.
    final name = 'mp${uid()}.jpg';
    try {
      await File('${dir.path}/$name').writeAsBytes(jpeg, flush: true);
      return name;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> read(String name) async {
    if (!isMealPhotoName(name)) return null;
    final dir = await _open();
    if (dir == null) return null;
    try {
      final f = File('${dir.path}/$name');
      if (!f.existsSync()) return null;
      return await f.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> delete(String name) async {
    if (!isMealPhotoName(name)) return;
    final dir = await _open();
    if (dir == null) return;
    try {
      final f = File('${dir.path}/$name');
      if (f.existsSync()) await f.delete();
    } catch (_) {/* already gone, or not ours to delete */}
  }

  @override
  Future<Set<String>?> sweep(Set<String> keep) async {
    final dir = await _open();
    if (dir == null) return null;
    try {
      final kept = <String>{};
      for (final e in dir.listSync()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (keep.contains(name)) {
          kept.add(name);
        } else {
          try {
            await e.delete();
          } catch (_) {/* someone else got there first */}
        }
      }
      return kept;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    final dir = await _open();
    if (dir == null) return;
    try {
      if (dir.existsSync()) await dir.delete(recursive: true);
      _dir = null;
    } catch (_) {/* nothing more to do about it */}
  }
}

/// Whether [name] is one of ours, and safe to join onto the photo directory.
///
/// This is a path traversal guard, not a formatting nicety. The name arrives from `AppState`, which
/// is read from a JSON file the user can edit and from any backup they were sent — `../../..` in a
/// `photo` field would otherwise point [FileMealPhotoStore.read] at an arbitrary file on the device
/// and [FileMealPhotoStore.delete] at destroying one. Only names this store writes get through.
bool isMealPhotoName(String name) =>
    RegExp(r'^mp[0-9a-z]{1,32}\.jpg$').hasMatch(name);

/// Reconciles the photos on disk against the photos the log still refers to, and returns the file
/// names whose references the caller should now drop.
///
/// One rule — *keep only what a recent meal still points at* — settles three different situations
/// that would each otherwise need their own pass:
///
///  - a photo older than [mealPhotoRetention], which ages out;
///  - a photo whose meal was deleted, which is an orphan taking up space;
///  - a reference restored from a backup onto a phone that has no such file, which is a name
///    pointing at nothing.
///
/// Age is taken from the meal's own day rather than the file's timestamp, because the day is what
/// the user sees and a file's mtime is whatever the last restore or sync happened to set.
///
/// When [keepPhotos] is false the keep set is empty, so switching the setting off is the same
/// operation as sweeping — there is no separate delete-everything path to keep in step with this
/// one.
Future<Set<String>> sweepMealPhotos(
  MealPhotoStore store,
  List<Meal> meals, {
  required bool keepPhotos,
  DateTime? now,
}) async {
  final cutoff = isoOf((now ?? DateTime.now()).subtract(mealPhotoRetention));
  final referenced = <String>{};
  if (keepPhotos) {
    for (final m in meals) {
      final p = m.photo;
      // ISO dates compare correctly as strings, which is half the reason the app stores them
      // that way.
      if (p != null && m.d.compareTo(cutoff) >= 0) referenced.add(p);
    }
  }

  final kept = await store.sweep(referenced);
  // Null means the directory could not be read. Nothing is known, so nothing is dropped.
  if (kept == null) return const {};

  return {
    for (final m in meals)
      if (m.photo != null && !kept.contains(m.photo)) m.photo!,
  };
}

/// The double for tests: a map, no disk, no platform channel.
class MemoryMealPhotoStore implements MealPhotoStore {
  MemoryMealPhotoStore([Map<String, Uint8List>? files])
      : files = {...?files};

  final Map<String, Uint8List> files;

  /// Makes [sweep] answer "I could not read the directory", the case that must not clear a single
  /// reference in the log.
  bool blind = false;

  /// A full disk, or a documents directory that will not open — [save] hands back null.
  bool refuseWrites = false;

  @override
  Future<String?> save(Uint8List jpeg) async {
    if (refuseWrites) return null;
    final name = 'mp${uid()}.jpg';
    files[name] = jpeg;
    return name;
  }

  @override
  Future<Uint8List?> read(String name) async =>
      isMealPhotoName(name) ? files[name] : null;

  @override
  Future<void> delete(String name) async {
    if (isMealPhotoName(name)) files.remove(name);
  }

  @override
  Future<Set<String>?> sweep(Set<String> keep) async {
    if (blind) return null;
    files.removeWhere((name, _) => !keep.contains(name));
    return files.keys.toSet();
  }

  @override
  Future<void> clear() async => files.clear();
}
