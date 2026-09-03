import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_wellness/data/models/app_state.dart';
import 'package:my_wellness/data/repositories/state_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    dir = Directory.systemTemp.createTempSync('mog_state_');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Future<StateRepository> repo() async =>
      StateRepository(prefs: await SharedPreferences.getInstance(), dir: dir);

  AppState withData({required int ts, required String routineName}) => AppState(
        ts: ts,
        routines: [Routine(id: 'r1', name: routineName)],
      );

  test('a fresh install boots to the defaults', () async {
    final s = await (await repo()).boot();
    expect(s.hasData, isFalse);
    expect(s.unit, 'kg');
  });

  test('saving writes both copies, and the mirror is the openGym file', () async {
    final r = await repo();
    await r.save(withData(ts: 100, routineName: 'Push Day'), immediate: true);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(StateRepository.prefsKey), isNotNull);

    final f = File('${dir.path}/${StateRepository.fileName}');
    expect(f.existsSync(), isTrue);
    final onDisk = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    expect((onDisk['routines'] as List).first['name'], 'Push Day');
  });

  test('a newer mirror wins at boot — the durable copy is the one to trust', () async {
    final r = await repo();
    File('${dir.path}/${StateRepository.fileName}')
        .writeAsStringSync(jsonEncode(withData(ts: 999, routineName: 'From the mirror').toJson()));
    (await SharedPreferences.getInstance()).setString(
        StateRepository.prefsKey, jsonEncode(withData(ts: 1, routineName: 'Stale').toJson()));

    expect((await r.boot()).routines.first.name, 'From the mirror');
  });

  test('a newer local copy is kept when the mirror lags behind', () async {
    final r = await repo();
    File('${dir.path}/${StateRepository.fileName}')
        .writeAsStringSync(jsonEncode(withData(ts: 1, routineName: 'Old mirror').toJson()));
    (await SharedPreferences.getInstance()).setString(
        StateRepository.prefsKey, jsonEncode(withData(ts: 999, routineName: 'Current').toJson()));

    expect((await r.boot()).routines.first.name, 'Current');
  });

  test('an empty local copy yields to the mirror however old it is', () async {
    // Preferences cleared by the OS, file still there: the training log comes back.
    final r = await repo();
    File('${dir.path}/${StateRepository.fileName}')
        .writeAsStringSync(jsonEncode(withData(ts: 1, routineName: 'Recovered').toJson()));
    expect((await r.boot()).routines.first.name, 'Recovered');
  });

  test('a debounced save is written by an explicit flush', () async {
    final r = await repo();
    await r.save(withData(ts: 5, routineName: 'Pending'));
    final f = File('${dir.path}/${StateRepository.fileName}');
    expect(f.existsSync(), isFalse, reason: 'the mirror waits out the debounce');

    await r.flush();
    expect(f.existsSync(), isTrue);
  });

  test('corrupt state on disk starts the app rather than stopping it', () async {
    final r = await repo();
    (await SharedPreferences.getInstance())
        .setString(StateRepository.prefsKey, 'not json at all');
    File('${dir.path}/${StateRepository.fileName}').writeAsStringSync('{ broken');
    final s = await r.boot();
    expect(s.unit, 'kg');
  });

  test('clear removes both copies', () async {
    final r = await repo();
    await r.save(withData(ts: 1, routineName: 'x'), immediate: true);
    await r.clear();
    expect(File('${dir.path}/${StateRepository.fileName}').existsSync(), isFalse);
    expect((await SharedPreferences.getInstance()).getString(StateRepository.prefsKey), isNull);
  });
}
