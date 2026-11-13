import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:so_do_what/core/data/database_recovery.dart';
import 'package:so_do_what/core/data/picker_store.dart';

void main() {
  late Directory directory;
  late String path;
  late RecoveryBackup backup;
  late DatabaseRecovery recovery;
  const oldBytes = [
    110,
    111,
    116,
    32,
    97,
    32,
    100,
    97,
    116,
    97,
    98,
    97,
    115,
    101,
  ];
  const walBytes = [119, 97, 108, 45, 102, 105, 120, 116, 117, 114, 101];
  const shmBytes = [115, 104, 109, 45, 102, 105, 120, 116, 117, 114, 101];
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('picker_recovery_');
    path = p.join(directory.path, 'picker.db');
    recovery = DatabaseRecovery(factory: databaseFactoryFfi);
    final source = await PickerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      randomIndex: (_) => 0,
    );
    try {
      final c = await source.saveCollection(
        name: '虚构恢复集合',
        drawMode: DrawMode.cycle,
        initialItems: '散步\n读书',
      );
      await source.draw(c.id, requestId: 'saved-record');
      await source.saveSettings(const PickerSettings(themeMode: 'dark'));
      backup = await recovery.prepareBackup(await source.exportBackup());
    } finally {
      await source.close();
    }
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<void> broken({bool sidecars = true}) async {
    await File(path).writeAsBytes(oldBytes, flush: true);
    if (sidecars) {
      await File('$path-wal').writeAsBytes(walBytes, flush: true);
      await File('$path-shm').writeAsBytes(shmBytes, flush: true);
    }
  }

  Future<void> restored() async {
    final store = await PickerStore.open(
      path: path,
      factory: databaseFactoryFfi,
    );
    try {
      expect((await store.listCollections()).single.name, '虚构恢复集合');
      expect((await store.history()).single.id, 'saved-record');
      expect((await store.settings()).themeMode, 'dark');
      expect(
        (await store.currentCycle((await store.listCollections()).single.id))!
            .consumedItemIds
            .length,
        1,
      );
    } finally {
      await store.close();
    }
  }

  Future<void> original() async {
    expect(await File(path).readAsBytes(), oldBytes);
    expect(await File('$path-wal').readAsBytes(), walBytes);
    expect(await File('$path-shm').readAsBytes(), shmBytes);
  }

  test('prepare rejects invalid backup and never changes original', () async {
    await broken();
    await expectLater(
      recovery.prepareBackup('{bad json'),
      throwsA(isA<AppFailure>()),
    );
    await original();
    expect(await File('$path.recovery.json').exists(), false);
  });
  test(
    'successful repair preserves exact faulty db WAL SHM and imports backup',
    () async {
      await broken();
      final result = await recovery.recover(path, backup);
      expect(result.restoredOriginal, false);
      expect(result.retainedPaths.length, 3);
      final base = result.retainedPaths.singleWhere(
        (e) => !e.endsWith('-wal') && !e.endsWith('-shm'),
      );
      expect(await File(base).readAsBytes(), oldBytes);
      expect(await File('$base-wal').readAsBytes(), walBytes);
      expect(await File('$base-shm').readAsBytes(), shmBytes);
      expect(await File('$path.recovery.json').exists(), false);
      await restored();
    },
  );
  for (final stage in [
    'replacementVerified',
    'markerWritten',
    'originalMovedDatabase',
    'originalMoved-wal',
    'originalMoved-shm',
    'originalRetained',
    'replacementInstalled',
  ]) {
    test('interruption $stage safely restores originals on startup', () async {
      await broken();
      final service = DatabaseRecovery(
        factory: databaseFactoryFfi,
        fault: (current) {
          if (current == stage) throw RecoveryInterruption(stage);
        },
      );
      await expectLater(
        service.recover(path, backup),
        throwsA(isA<RecoveryInterruption>()),
      );
      final result = await recovery.recoverInterrupted(path);
      if (stage != 'replacementVerified') {
        expect(result!.restoredOriginal, true);
        expect(
          result.retainedPaths.where((e) => e.contains('.damaged-')).length,
          3,
        );
      } else {
        expect(result, null);
      }
      await original();
      expect(await recovery.recoverInterrupted(path), null);
    });
  }
  test(
    'interruption after durable commit keeps verified new database',
    () async {
      await broken();
      final service = DatabaseRecovery(
        factory: databaseFactoryFfi,
        fault: (stage) {
          if (stage == 'commitWritten') throw RecoveryInterruption(stage);
        },
      );
      await expectLater(
        service.recover(path, backup),
        throwsA(isA<RecoveryInterruption>()),
      );
      final result = await recovery.recoverInterrupted(path);
      expect(result!.restoredOriginal, false);
      expect(result.retainedPaths.length, 3);
      await restored();
    },
  );
  test(
    'ordinary replacement error immediately rolls back and preserves originals',
    () async {
      await broken();
      final service = DatabaseRecovery(
        factory: databaseFactoryFfi,
        fault: (stage) {
          if (stage == 'replacementInstalled') {
            throw StateError('injected rename-adjacent failure');
          }
        },
      );
      await expectLater(service.recover(path, backup), throwsStateError);
      await original();
      expect(await File('$path.recovery.json').exists(), false);
      expect(
        directory
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('.damaged-'))
            .length,
        3,
      );
    },
  );
  test('tampered recovery marker paths cannot escape database directory', () async {
    await broken();
    final outside = File(
      p.join(
        directory.parent.path,
        'recovery_sentinel_${directory.uri.pathSegments.where((e) => e.isNotEmpty).last}',
      ),
    );
    await outside.writeAsString('retain');
    try {
      for (final id in [
        '../../sentinel',
        r'..\..\sentinel',
        outside.path,
        'not-a-uuid',
      ]) {
        await File('$path.recovery.json').writeAsString(
          jsonEncode({
            'schemaVersion': 1,
            'databaseName': 'picker.db',
            'id': id,
            'originalExists': {'': true, '-wal': true, '-shm': true},
          }),
        );
        await expectLater(
          recovery.recoverInterrupted(path),
          throwsA(isA<AppFailure>()),
        );
        await original();
        expect(await outside.readAsString(), 'retain');
      }
      await File('$path.recovery.json').writeAsString(
        jsonEncode({
          'schemaVersion': 1,
          'databaseName': '../another.db',
          'id': 'd50bb358-985c-4d12-84be-bc32782cb683',
          'originalExists': {'': true, '-wal': true, '-shm': true},
        }),
      );
      await expectLater(
        recovery.recoverInterrupted(path),
        throwsA(isA<AppFailure>()),
      );
      await original();
    } finally {
      await outside.delete();
    }
  });
  test(
    'malformed and oversized markers fail closed without changing files',
    () async {
      await broken();
      for (final value in [
        '{bad',
        'x' * 8193,
        jsonEncode({'schemaVersion': 1}),
      ]) {
        await File('$path.recovery.json').writeAsString(value);
        await expectLater(
          recovery.recoverInterrupted(path),
          throwsA(isA<AppFailure>()),
        );
        await original();
      }
    },
  );
  test(
    'newer valid database refuses backup replacement with all bytes intact',
    () async {
      final db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (db, _) =>
              db.execute('CREATE TABLE future_content(value TEXT)'),
        ),
      );
      await db.insert('future_content', {'value': 'future-fixture'});
      await db.close();
      final bytes = await File(path).readAsBytes();
      await expectLater(
        recovery.recover(path, backup),
        throwsA(
          isA<AppFailure>().having((e) => e.code, 'code', 'unsupportedVersion'),
        ),
      );
      expect(await File(path).readAsBytes(), bytes);
      expect(await File('$path.recovery.json').exists(), false);
    },
  );
  test('fresh path and interrupted first-install keep candidate without creating empty db', () async {
    final service = DatabaseRecovery(
      factory: databaseFactoryFfi,
      fault: (stage) {
        if (stage == 'replacementInstalled') throw RecoveryInterruption(stage);
      },
    );
    await expectLater(
      service.recover(path, backup),
      throwsA(isA<RecoveryInterruption>()),
    );
    final result = await recovery.recoverInterrupted(path);
    expect(result!.restoredOriginal, true);
    expect(await File(path).exists(), false);
    expect(result.retainedPaths.any((e) => e.contains('.interrupted-')), true);
    await recovery.recover(path, backup);
    await restored();
  });
  for (final copyStage in [
    'rollbackCopiedDatabase',
    'rollbackCopied-wal',
    'rollbackCopied-shm',
  ]) {
    test(
      'rollback interruption $copyStage can be repeated without data loss',
      () async {
        await broken();
        final stopped = DatabaseRecovery(
          factory: databaseFactoryFfi,
          fault: (stage) {
            if (stage == 'replacementInstalled') {
              throw RecoveryInterruption(stage);
            }
          },
        );
        await expectLater(
          stopped.recover(path, backup),
          throwsA(isA<RecoveryInterruption>()),
        );
        final rollback = DatabaseRecovery(
          factory: databaseFactoryFfi,
          fault: (stage) {
            if (stage == copyStage) throw RecoveryInterruption(stage);
          },
        );
        await expectLater(
          rollback.recoverInterrupted(path),
          throwsA(isA<RecoveryInterruption>()),
        );
        expect(await File('$path.recovery.json').exists(), true);
        final result = await recovery.recoverInterrupted(path);
        expect(result!.restoredOriginal, true);
        await original();
        expect(
          result.retainedPaths.where((e) => e.contains('.damaged-')).length,
          3,
        );
      },
    );
  }
  test(
    'newer schema present only in real WAL also refuses replacement',
    () async {
      final sourcePath = '$path.source';
      final db = await databaseFactoryFfi.openDatabase(
        sourcePath,
        options: OpenDatabaseOptions(
          onConfigure: (db) async {
            await db.rawQuery('PRAGMA journal_mode=WAL');
            await db.execute('PRAGMA wal_autocheckpoint=0');
          },
        ),
      );
      try {
        await db.execute('CREATE TABLE future_data(value TEXT)');
        await db.execute('PRAGMA user_version=2');
        await db.insert('future_data', {'value': 'only-in-wal'});
        for (final suffix in ['', '-wal', '-shm']) {
          final source = File('$sourcePath$suffix');
          if (await source.exists()) await source.copy('$path$suffix');
        }
      } finally {
        await db.close();
      }
      final snapshot = <String, List<int>>{};
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File('$path$suffix');
        if (await file.exists()) snapshot[suffix] = await file.readAsBytes();
      }
      expect(snapshot.containsKey('-wal'), true);
      await expectLater(
        recovery.recover(path, backup),
        throwsA(
          isA<AppFailure>().having((e) => e.code, 'code', 'unsupportedVersion'),
        ),
      );
      for (final entry in snapshot.entries) {
        expect(await File('$path${entry.key}').readAsBytes(), entry.value);
      }
    },
  );
}
