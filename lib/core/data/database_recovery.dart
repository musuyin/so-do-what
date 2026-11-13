import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'picker_store.dart';

/// A validated, immutable backup. Recovery validates it again in a fresh DB.
class RecoveryBackup {
  final BackupPreview preview;
  const RecoveryBackup._(this.preview);
}

class RecoveryResult {
  final List<String> retainedPaths;
  final bool restoredOriginal;
  RecoveryResult(
    Iterable<String> retainedPaths, {
    this.restoredOriginal = false,
  }) : retainedPaths = List.unmodifiable(retainedPaths);
}

/// Test-only fault used to model process termination without running cleanup.
class RecoveryInterruption implements Exception {
  final String stage;
  const RecoveryInterruption(this.stage);
}

/// Recovery requires every handle to [path] to be closed by the caller.
/// Faulty files are renamed to permanent retained siblings, never deleted.
/// Only generated version probes and completed operation metadata are deleted.
class DatabaseRecovery {
  DatabaseRecovery({DatabaseFactory? factory, this.fault})
    : _factory = factory ?? databaseFactory;

  final DatabaseFactory _factory;
  final void Function(String stage)? fault;
  static final Set<String> _active = {};
  static const _suffixes = ['', '-wal', '-shm'];
  static const _markerSuffix = '.recovery.json';

  Future<RecoveryBackup> prepareBackup(String text) async {
    final store = await PickerStore.open(
      path: inMemoryDatabasePath,
      factory: _factory,
    );
    try {
      final preview = store.validateBackup(text);
      // Applying the backup exercises SQL constraints as well as JSON validation.
      await store.restoreBackup(preview);
      final canonical = store.validateBackup(await store.exportBackup());
      // Keep the original exported-at value for the confirmation preview.
      return RecoveryBackup._(
        BackupPreview.validated(
          canonical.json,
          preview.exportedAt,
          canonical.collectionCount,
          canonical.itemCount,
          canonical.recordCount,
        ),
      );
    } finally {
      await store.close();
    }
  }

  String _absolute(String path) => p.normalize(p.absolute(path));
  String _retained(String path, String id) => '$path.damaged-$id';
  String _replacement(String path, String id) => '$path.replacement-$id';
  String _interrupted(String path, String id) => '$path.interrupted-$id';
  String _commit(String path, String id) => '$path.recovery-$id.committed';

  Future<T> _exclusive<T>(String path, Future<T> Function() work) async {
    final key = Platform.isWindows ? path.toLowerCase() : path;
    if (!_active.add(key)) {
      throw const AppFailure('conflict', '数据修复正在进行，请稍候');
    }
    try {
      return await work();
    } finally {
      _active.remove(key);
    }
  }

  Future<RecoveryResult> recover(String path, RecoveryBackup backup) {
    final absolute = _absolute(path);
    return _exclusive(absolute, () => _recover(absolute, backup));
  }

  Future<RecoveryResult> _recover(String path, RecoveryBackup backup) async {
    await _recoverInterrupted(path);
    await _assertSupportedOriginal(path);
    await Directory(p.dirname(path)).create(recursive: true);
    final id = const Uuid().v4();
    final candidate = _replacement(path, id);
    final retained = _retained(path, id);
    final marker = File('$path$_markerSuffix');
    final commit = File(_commit(path, id));
    try {
      final store = await PickerStore.open(path: candidate, factory: _factory);
      try {
        final checked = store.validateBackup(backup.preview.json);
        await store.restoreBackup(checked);
        store.validateBackup(await store.exportBackup());
      } finally {
        await store.close();
      }
      await _verifyDatabase(candidate);
      fault?.call('replacementVerified');
      final exists = <String, bool>{};
      for (final suffix in _suffixes) {
        exists[suffix] = await File('$path$suffix').exists();
      }
      final plan = {
        'schemaVersion': 1,
        'databaseName': p.basename(path),
        'id': id,
        'originalExists': exists,
      };
      // Immutable intent is installed before the first original-file move.
      final tempMarker = File('${marker.path}.tmp-$id');
      await tempMarker.writeAsString(jsonEncode(plan), flush: true);
      await tempMarker.rename(marker.path);
      fault?.call('markerWritten');
      for (final suffix in _suffixes) {
        if (exists[suffix]!) {
          await File('$path$suffix').rename('$retained$suffix');
          fault?.call('originalMoved${suffix.isEmpty ? 'Database' : suffix}');
        }
      }
      fault?.call('originalRetained');
      await File(candidate).rename(path);
      fault?.call('replacementInstalled');
      await _verifyDatabase(path);
      // Only this durable, immutable receipt makes installation committed.
      await commit.writeAsString(id, flush: true);
      fault?.call('commitWritten');
      await _finishCommittedMetadata(marker, commit);
      return RecoveryResult(await _existingArtifacts(retained));
    } catch (error) {
      if (error is RecoveryInterruption) rethrow;
      if (await marker.exists()) {
        try {
          final reconciled = await _recoverInterrupted(path);
          if (reconciled != null && !reconciled.restoredOriginal) {
            return reconciled;
          }
        } catch (_) {
          throw const AppFailure(
            'recoveryBlocked',
            '修复未完成，原数据文件已保留。请保留应用数据并重试，暂勿清除应用数据。',
          );
        }
      }
      rethrow;
    }
  }

  Future<void> _assertSupportedOriginal(String path) async {
    if (!await File(path).exists()) return;
    // Even a read-only SQLite connection can rewrite SHM. Probe copies, never
    // the faulty original or its sidecars, before deciding version support.
    final probe = '$path.version-probe-${const Uuid().v4()}';
    Database? db;
    try {
      for (final suffix in _suffixes) {
        final source = File('$path$suffix');
        if (await source.exists()) await source.copy('$probe$suffix');
      }
      db = await _factory.openDatabase(
        probe,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      final version = Sqflite.firstIntValue(
        await db.rawQuery('PRAGMA user_version'),
      );
      if (version != null && version > 1) {
        throw const AppFailure('unsupportedVersion', '这份数据需要更新版本的应用，请先更新应用');
      }
    } on AppFailure {
      rethrow;
    } on DatabaseException {
      // A genuinely corrupt database cannot report a version. It is retained
      // untouched by the replacement operation; no blank initialization occurs.
    } finally {
      await db?.close();
      for (final suffix in _suffixes) {
        final file = File('$probe$suffix');
        if (await file.exists()) await file.delete();
      }
    }
  }

  Future<RecoveryResult?> recoverInterrupted(String path) {
    final absolute = _absolute(path);
    return _exclusive(absolute, () => _recoverInterrupted(absolute));
  }

  Future<RecoveryResult?> _recoverInterrupted(String path) async {
    final marker = File('$path$_markerSuffix');
    if (!await marker.exists()) return null;
    final plan = await _readPlan(marker, path);
    final id = plan['id'] as String;
    final existed = (plan['originalExists'] as Map).cast<String, bool>();
    final retained = _retained(path, id);
    final candidate = _replacement(path, id);
    final interrupted = _interrupted(path, id);
    final commit = File(_commit(path, id));
    if (await commit.exists() && await commit.readAsString() == id) {
      var valid = false;
      try {
        await _verifyDatabase(path);
        valid = true;
      } catch (_) {
        // Receipt alone cannot authorize use of an invalid replacement.
      }
      if (valid) {
        await _finishCommittedMetadata(marker, commit);
        return RecoveryResult(await _existingArtifacts(retained));
      }
    }
    // If retention was interrupted mid-move, unmoved original files remain in
    // place. Move them into the same permanent set before restoring copies.
    // A replacement is only installed after ALL originals have been retained.
    final originalsFullyRetained = await _allRetained(existed, retained);
    if (!originalsFullyRetained) {
      for (final suffix in _suffixes) {
        if (existed[suffix]! && !await File('$retained$suffix').exists()) {
          final original = File('$path$suffix');
          if (!await original.exists()) {
            throw const AppFailure('recoveryBlocked', '原数据文件暂不可访问，已保留修复线索');
          }
          await original.rename('$retained$suffix');
        }
      }
    }
    // Preserve any installed replacement before restoring the original bytes.
    // Existing interrupted copies mean a prior rollback already preserved it.
    for (final suffix in _suffixes) {
      final current = File('$path$suffix');
      final kept = File('$interrupted$suffix');
      if (await current.exists() && !await kept.exists()) {
        await current.rename(kept.path);
      }
    }
    for (final suffix in _suffixes) {
      if (existed[suffix]!) {
        final source = File('$retained$suffix');
        if (!await source.exists()) {
          throw const AppFailure('recoveryBlocked', '原数据文件暂不可访问，已保留修复线索');
        }
        await source.copy('$path$suffix');
        fault?.call('rollbackCopied${suffix.isEmpty ? 'Database' : suffix}');
      }
    }
    // Keep marker until every copy has completed. A second interruption simply
    // repeats these copies from retained files, never from partially copied DBs.
    await marker.delete();
    if (await commit.exists()) await commit.delete();
    final paths = <String>[
      ...await _existingArtifacts(retained),
      ...await _existingArtifacts(candidate),
      ...await _existingArtifacts(interrupted),
    ];
    return RecoveryResult(paths, restoredOriginal: true);
  }

  Future<bool> _allRetained(Map<String, bool> existed, String retained) async {
    for (final suffix in _suffixes) {
      if (existed[suffix]! && !await File('$retained$suffix').exists()) {
        return false;
      }
    }
    return true;
  }

  Future<void> _finishCommittedMetadata(File marker, File commit) async {
    // Once committed and verified, metadata cleanup failure must not undo the
    // installation. Keep the receipt whenever the intent could not be removed.
    try {
      if (await marker.exists()) await marker.delete();
    } on FileSystemException {
      return;
    }
    try {
      if (await commit.exists()) await commit.delete();
    } on FileSystemException {
      // An orphaned receipt has no effect without its intent marker.
    }
  }

  Future<Map<String, dynamic>> _readPlan(File marker, String path) async {
    try {
      if (await marker.length() > 8192) throw const FormatException();
      final m = jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
      if (m['schemaVersion'] != 1 || m['databaseName'] != p.basename(path)) {
        throw const FormatException();
      }
      final id = m['id'];
      if (id is! String ||
          !RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ).hasMatch(id)) {
        throw const FormatException();
      }
      final original = m['originalExists'] as Map;
      if (original.length != 3 ||
          !_suffixes.every(
            (s) => original.containsKey(s) && original[s] is bool,
          )) {
        throw const FormatException();
      }
      // All artifact paths are derived here from the checked UUID and the
      // caller's database path. No file path from the marker is trusted.
      return m;
    } catch (_) {
      throw const AppFailure('recoveryBlocked', '修复记录无法读取，原文件未更改。请保留应用数据以便检查。');
    }
  }

  Future<void> _verifyDatabase(String path) async {
    final db = await _factory.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    try {
      final quick = await db.rawQuery('PRAGMA quick_check');
      if (quick.length != 1 || quick.single.values.single != 'ok') {
        throw const AppFailure('recoveryBlocked', '新数据文件未通过完整性检查');
      }
      final relations = await db.rawQuery('PRAGMA foreign_key_check');
      if (relations.isNotEmpty) {
        throw const AppFailure('recoveryBlocked', '新数据文件存在不完整的关联');
      }
    } finally {
      await db.close();
    }
  }

  Future<List<String>> _existingArtifacts(String base) async {
    final result = <String>[];
    for (final suffix in _suffixes) {
      final file = File('$base$suffix');
      if (await file.exists()) result.add(file.path);
    }
    return result;
  }
}
