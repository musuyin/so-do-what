import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../domain/models.dart';
export '../domain/models.dart';

class PickerStore {
  final Database _db;
  final int Function(int) _random;
  final DateTime Function() _clock;
  final String Function() newId;
  final void Function(String)? fault;
  Future<void> _tail = Future.value();
  int generation = 0;
  final Map<String, ({String fingerprint, DrawRecord record})> _prepared = {};
  PickerStore._(this._db, this._random, this._clock, this.newId, this.fault);
  static Future<PickerStore> open({
    String? path,
    DatabaseFactory? factory,
    int Function(int)? randomIndex,
    DateTime Function()? clock,
    String Function()? newId,
    void Function(String)? fault,
  }) async {
    final f = factory ?? databaseFactory;
    final location =
        path ?? p.join(await f.getDatabasesPath(), 'so_do_what.db');
    final db = await f.openDatabase(
      location,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onCreate: (db, v) async {
          await db.execute(
            'CREATE TABLE collections(id TEXT PRIMARY KEY,payload TEXT NOT NULL,sort_order INTEGER NOT NULL CHECK(sort_order>=0),archived INTEGER NOT NULL CHECK(archived IN(0,1)))',
          );
          await db.execute(
            'CREATE TABLE items(id TEXT PRIMARY KEY,collection_id TEXT NOT NULL REFERENCES collections(id),title_key TEXT NOT NULL,payload TEXT NOT NULL,sort_order INTEGER NOT NULL CHECK(sort_order>=0),archived INTEGER NOT NULL CHECK(archived IN(0,1)),UNIQUE(collection_id,title_key),UNIQUE(id,collection_id))',
          );
          await db.execute(
            'CREATE TABLE cycles(id TEXT PRIMARY KEY,collection_id TEXT NOT NULL REFERENCES collections(id),sequence INTEGER NOT NULL CHECK(sequence>0),payload TEXT NOT NULL,UNIQUE(collection_id,sequence),UNIQUE(id,collection_id))',
          );
          await db.execute(
            'CREATE TABLE draw_records(id TEXT PRIMARY KEY,collection_id TEXT NOT NULL REFERENCES collections(id),item_id TEXT NOT NULL,cycle_id TEXT,title_snapshot TEXT NOT NULL,completed_at INTEGER,mode TEXT NOT NULL CHECK(mode IN ("allowRepeat","avoidPrevious","cycle")),payload TEXT NOT NULL,status TEXT NOT NULL CHECK(status IN ("pending","completed","skipped")),drawn_at INTEGER NOT NULL,draw_ordinal INTEGER UNIQUE NOT NULL,revision INTEGER NOT NULL DEFAULT 0,CHECK((status="completed")=(completed_at IS NOT NULL)),CHECK((mode="cycle")=(cycle_id IS NOT NULL)),FOREIGN KEY(item_id,collection_id) REFERENCES items(id,collection_id),FOREIGN KEY(cycle_id,collection_id) REFERENCES cycles(id,collection_id))',
          );
          await db.execute(
            'CREATE TABLE cycle_consumptions(cycle_id TEXT NOT NULL,collection_id TEXT NOT NULL,item_id TEXT NOT NULL,PRIMARY KEY(cycle_id,item_id),FOREIGN KEY(cycle_id,collection_id) REFERENCES cycles(id,collection_id),FOREIGN KEY(item_id,collection_id) REFERENCES items(id,collection_id))',
          );
          await db.execute(
            'CREATE TABLE settings(id INTEGER PRIMARY KEY CHECK(id=1),payload TEXT NOT NULL)',
          );
          await db.insert('settings', {
            'id': 1,
            'payload': jsonEncode(const PickerSettings().toJson()),
          });
          for (final sql in [
            'CREATE INDEX items_order ON items(collection_id,sort_order,id)',
            'CREATE INDEX records_collection ON draw_records(collection_id,draw_ordinal DESC)',
            'CREATE INDEX records_time ON draw_records(drawn_at DESC,draw_ordinal DESC)',
            'CREATE INDEX records_status ON draw_records(status,drawn_at DESC,draw_ordinal DESC)',
            'CREATE INDEX records_filter ON draw_records(collection_id,status,drawn_at DESC,draw_ordinal DESC)',
          ]) {
            await db.execute(sql);
          }
        },
        onDowngrade: (db, oldVersion, newVersion) =>
            throw const AppFailure('unsupportedVersion', '这份数据需要更新版本的应用'),
      ),
    );
    final rng = Random.secure();
    return PickerStore._(
      db,
      randomIndex ?? rng.nextInt,
      clock ?? DateTime.now,
      newId ?? const Uuid().v4,
      fault,
    );
  }

  DateTime get _now => DateTime.fromMillisecondsSinceEpoch(
    _clock().toUtc().millisecondsSinceEpoch,
    isUtc: true,
  );
  Future<T> _write<T>(
    Future<T> Function(Transaction) action, {
    bool replacesData = false,
  }) {
    final expected = generation;
    final result = _tail.then((_) async {
      if (expected != generation) {
        throw const AppFailure('conflict', '数据已更新，请重新打开页面');
      }
      final value = await _db.transaction(action);
      if (replacesData) {
        generation++;
        _prepared.clear();
      }
      return value;
    });
    _tail = result.then<void>((_) {}, onError: (Object e, StackTrace s) {});
    return result;
  }

  Map<String, dynamic> _payload(Map<String, Object?> row) =>
      jsonDecode(row['payload'] as String) as Map<String, dynamic>;
  Collection _collection(Map<String, Object?> row) =>
      Collection.fromJson(_payload(row));
  Item _item(Map<String, Object?> row) => Item.fromJson(_payload(row));
  DrawRecord _record(Map<String, Object?> row) => DrawRecord.fromJson(
    _payload(row),
    ordinal: row['draw_ordinal'] as int,
    revision: row['revision'] as int,
    appGeneration: generation,
  );
  Future<Collection> _getCollection(DatabaseExecutor db, String id) async {
    final rows = await db.query('collections', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) {
      throw const AppFailure('conflict', '集合已不存在');
    }
    return _collection(rows.single);
  }

  Future<Collection> getCollection(String id) => _getCollection(_db, id);
  void _editable(Collection c) {
    if (c.archived) {
      throw const AppFailure('archived', '请先恢复这个集合');
    }
  }

  Future<List<Collection>> listCollections({
    bool archived = false,
    String search = '',
  }) async =>
      (await _db.query(
            'collections',
            where: 'archived=?',
            whereArgs: [archived ? 1 : 0],
            orderBy: 'sort_order,id',
          ))
          .map(_collection)
          .where(
            (c) =>
                c.name.contains(normalized(search)) ||
                c.description.contains(normalized(search)),
          )
          .toList();
  Future<List<Item>> listItems(
    String collectionId, {
    bool archived = false,
    String search = '',
  }) async =>
      (await _db.query(
            'items',
            where: 'collection_id=? AND archived=?',
            whereArgs: [collectionId, archived ? 1 : 0],
            orderBy: 'sort_order,id',
          ))
          .map(_item)
          .where(
            (i) =>
                i.title.contains(normalized(search)) ||
                i.note.contains(normalized(search)),
          )
          .toList();
  Future<void> _putCollection(
    DatabaseExecutor db,
    Collection c, {
    bool insert = false,
  }) async {
    final values = {
      'payload': jsonEncode(c.toJson()),
      'sort_order': c.sortOrder,
      'archived': c.archived ? 1 : 0,
    };
    if (insert) {
      await db.insert('collections', {'id': c.id, ...values});
    } else {
      await db.update('collections', values, where: 'id=?', whereArgs: [c.id]);
    }
  }

  Future<void> _putItem(
    DatabaseExecutor db,
    Item i, {
    bool insert = false,
  }) async {
    final values = {
      'payload': jsonEncode(i.toJson()),
      'title_key': normalized(i.title),
      'sort_order': i.sortOrder,
      'archived': i.archived ? 1 : 0,
    };
    if (insert) {
      await db.insert('items', {
        'id': i.id,
        'collection_id': i.collectionId,
        ...values,
      });
    } else {
      await db.update('items', values, where: 'id=?', whereArgs: [i.id]);
    }
  }

  Future<int> _count(
    DatabaseExecutor db,
    String table, {
    String? collectionId,
  }) async => Sqflite.firstIntValue(
    await db.rawQuery(
      'SELECT COUNT(*) FROM $table${collectionId == null ? '' : ' WHERE collection_id=?'}',
      collectionId == null ? [] : [collectionId],
    ),
  )!;
  Future<int> _nextOrder(
    DatabaseExecutor db,
    String table, {
    String? collectionId,
  }) async => (Sqflite.firstIntValue(
    await db.rawQuery(
      'SELECT COALESCE(MAX(sort_order),-1)+1 FROM $table${collectionId == null ? '' : ' WHERE collection_id=?'}',
      collectionId == null ? [] : [collectionId],
    ),
  )!);
  Future<Collection> saveCollection({
    String? id,
    required String name,
    String description = '',
    String executionCriterion = '',
    String iconKey = 'dice',
    String colorKey = 'sage',
    DrawMode drawMode = DrawMode.allowRepeat,
    PresentationStyle presentationStyle = PresentationStyle.gacha,
    String initialItems = '',
  }) => _write((tx) async {
    name = checkedText(name, 40, required: true);
    description = checkedText(description, 200, multiline: true);
    executionCriterion = checkedText(executionCriterion, 120, multiline: true);
    if (![
          'dice',
          'movie',
          'book',
          'game',
          'food',
          'walk',
          'music',
          'star',
        ].contains(iconKey) ||
        !['sage', 'lavender', 'sky', 'peach'].contains(colorKey)) {
      throw const AppFailure('validation', '请选择可用图标和颜色');
    }
    final old = id == null ? null : await _getCollection(tx, id);
    if (old != null) {
      _editable(old);
    } else if (await _count(tx, 'collections') >= 100) {
      throw const AppFailure('capacity', '最多可保存 100 个集合（包括归档）');
    }
    final now = _now;
    final c = Collection(
      id: id ?? newId(),
      name: name,
      description: description,
      executionCriterion: executionCriterion,
      iconKey: iconKey,
      colorKey: colorKey,
      drawMode: drawMode,
      presentationStyle: presentationStyle,
      sortOrder: old?.sortOrder ?? await _nextOrder(tx, 'collections'),
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    await _putCollection(tx, c, insert: old == null);
    if (old == null && initialItems.isNotEmpty) {
      await _import(tx, c.id, initialItems);
    }
    if (drawMode == DrawMode.cycle && await _cycle(tx, c.id) == null) {
      await _newCycle(tx, c.id);
    }
    return c;
  });
  Future<Item> saveItem({
    String? id,
    required String collectionId,
    required String title,
    String note = '',
    bool enabled = true,
  }) => _write((tx) async {
    _editable(await _getCollection(tx, collectionId));
    title = checkedText(title, 100, required: true);
    note = checkedText(note, 300, multiline: true);
    final rows = id == null
        ? <Map<String, Object?>>[]
        : await tx.query(
            'items',
            where: 'id=? AND collection_id=?',
            whereArgs: [id, collectionId],
          );
    if (id != null && rows.isEmpty) {
      throw const AppFailure('conflict', '选项已不存在');
    }
    final old = rows.isEmpty ? null : _item(rows.single);
    if (old == null &&
        await _count(tx, 'items', collectionId: collectionId) >= 1000) {
      throw const AppFailure('capacity', '每个集合最多 1,000 个选项（包括停用和归档）');
    }
    final duplicates = await tx.query(
      'items',
      where: 'collection_id=? AND title_key=? AND id<>?',
      whereArgs: [collectionId, title, id ?? ''],
    );
    if (duplicates.isNotEmpty) {
      throw const AppFailure('validation', '这个标题已经存在，请查看停用或归档选项');
    }
    final now = _now;
    final i = Item(
      id: id ?? newId(),
      collectionId: collectionId,
      title: title,
      note: note,
      enabled: enabled,
      archivedAt: old?.archivedAt,
      sortOrder:
          old?.sortOrder ??
          await _nextOrder(tx, 'items', collectionId: collectionId),
      createdAt: old?.createdAt ?? now,
      updatedAt: now,
    );
    await _putItem(tx, i, insert: old == null);
    return i;
  });
  Future<void> archiveCollection(String id, bool archive) => _write((tx) async {
    final c = await _getCollection(tx, id);
    final m = c.toJson();
    m['archivedAt'] = archive ? _now.toIso8601String() : null;
    m['updatedAt'] = _now.toIso8601String();
    await _putCollection(tx, Collection.fromJson(m));
  });
  Future<void> archiveItem(String id, bool archive) => _write((tx) async {
    final rows = await tx.query('items', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) {
      throw const AppFailure('conflict', '选项已不存在');
    }
    final i = _item(rows.single);
    _editable(await _getCollection(tx, i.collectionId));
    final m = i.toJson();
    m['archivedAt'] = archive ? _now.toIso8601String() : null;
    m['updatedAt'] = _now.toIso8601String();
    await _putItem(tx, Item.fromJson(m));
  });
  Future<void> reorderCollections(List<String> ids) =>
      _reorder('collections', ids);
  Future<void> reorderItems(String collectionId, List<String> ids) =>
      _reorder('items', ids, collectionId: collectionId);
  Future<void> _reorder(
    String table,
    List<String> ids, {
    String? collectionId,
  }) => _write((tx) async {
    if (collectionId != null) {
      _editable(await _getCollection(tx, collectionId));
    }
    final rows = await tx.query(
      table,
      where: collectionId == null ? null : 'collection_id=?',
      whereArgs: collectionId == null ? null : [collectionId],
    );
    if (ids.length != rows.length ||
        ids.toSet().length != ids.length ||
        !rows.every((r) => ids.contains(r['id']))) {
      throw const AppFailure('conflict', '列表已变化，请重新调整顺序');
    }
    for (var n = 0; n < ids.length; n++) {
      final row = rows.firstWhere((r) => r['id'] == ids[n]);
      final m = _payload(row);
      m['sortOrder'] = n;
      await tx.update(
        table,
        {'sort_order': n, 'payload': jsonEncode(m)},
        where: 'id=?',
        whereArgs: [ids[n]],
      );
    }
  });
  Future<BatchPreview> previewImport(String collectionId, String text) =>
      _preview(_db, collectionId, text);
  Future<BatchPreview> _preview(
    DatabaseExecutor db,
    String collectionId,
    String text,
  ) async {
    final lines = text.split(RegExp(r'\r\n|\n|\r'));
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    if (lines.length > 500) {
      throw const AppFailure('capacity', '每批最多 500 行');
    }
    final existing = (await db.query(
      'items',
      columns: ['title_key'],
      where: 'collection_id=?',
      whereArgs: [collectionId],
    )).map((e) => e['title_key']).toSet();
    final seen = <String>{};
    final result = <ImportLine>[];
    for (var n = 0; n < lines.length; n++) {
      final t = normalized(lines[n]);
      ImportKind kind;
      try {
        checkedText(t, 100, required: true);
        kind = existing.contains(t)
            ? ImportKind.duplicateExisting
            : !seen.add(t)
            ? ImportKind.duplicateBatch
            : ImportKind.added;
      } on AppFailure {
        kind = t.isEmpty ? ImportKind.blank : ImportKind.invalid;
      }
      result.add(ImportLine(n + 1, t, kind));
    }
    return BatchPreview(result);
  }

  Future<void> importItems(String collectionId, String text) =>
      _write((tx) => _import(tx, collectionId, text));
  Future<void> _import(
    DatabaseExecutor tx,
    String collectionId,
    String text,
  ) async {
    _editable(await _getCollection(tx, collectionId));
    final preview = await _preview(tx, collectionId, text);
    if (preview.invalid > 0) {
      throw const AppFailure('validation', '有选项超过长度限制或含无效字符，请返回修正');
    }
    if (!preview.canSave) {
      return;
    }
    if (await _count(tx, 'items', collectionId: collectionId) + preview.added >
        1000) {
      throw const AppFailure('capacity', '新增后将超过每集合 1,000 个选项');
    }
    var order = await _nextOrder(tx, 'items', collectionId: collectionId);
    final now = _now;
    for (final title in preview.titles) {
      await _putItem(
        tx,
        Item(
          id: newId(),
          collectionId: collectionId,
          title: title,
          sortOrder: order++,
          createdAt: now,
          updatedAt: now,
        ),
        insert: true,
      );
    }
  }

  Future<CollectionCycle?> _cycle(
    DatabaseExecutor db,
    String collectionId,
  ) async {
    final rows = await db.query(
      'cycles',
      where: 'collection_id=?',
      whereArgs: [collectionId],
      orderBy: 'sequence DESC',
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    final m = _payload(rows.single);
    m['consumedItemIds'] = (await db.query(
      'cycle_consumptions',
      columns: ['item_id'],
      where: 'cycle_id=?',
      whereArgs: [m['id']],
    )).map((e) => e['item_id']).toList();
    return CollectionCycle.fromJson(m);
  }

  Future<CollectionCycle?> currentCycle(String collectionId) =>
      _cycle(_db, collectionId);
  Future<CollectionCycle> _newCycle(
    DatabaseExecutor db,
    String collectionId,
  ) async {
    final old = await _cycle(db, collectionId);
    final c = CollectionCycle(
      id: newId(),
      collectionId: collectionId,
      sequence: (old?.sequence ?? 0) + 1,
      createdAt: _now,
    );
    await db.insert('cycles', {
      'id': c.id,
      'collection_id': collectionId,
      'sequence': c.sequence,
      'payload': jsonEncode(c.toJson()),
    });
    return c;
  }

  Future<CollectionCycle> startNextCycle(
    String collectionId, {
    String? expectedCycleId,
  }) => _write((tx) async {
    _editable(await _getCollection(tx, collectionId));
    final old = await _cycle(tx, collectionId);
    if (old != null && old.id != expectedCycleId) {
      return old;
    }
    return _newCycle(tx, collectionId);
  });
  Future<DrawRecord?> reconcile(String requestId) async {
    final rows = await _db.query(
      'draw_records',
      where: 'id=?',
      whereArgs: [requestId],
    );
    return rows.isEmpty ? null : _record(rows.single);
  }

  Future<DrawRecord> draw(
    String collectionId, {
    required String requestId,
  }) async {
    try {
      final committed = await _write((tx) async {
        final existing = await tx.query(
          'draw_records',
          where: 'id=?',
          whereArgs: [requestId],
        );
        if (existing.isNotEmpty) {
          final record = _record(existing.single);
          if (record.collectionId != collectionId) {
            throw const AppFailure('conflict', '抽取请求不匹配');
          }
          return record;
        }
        final c = await _getCollection(tx, collectionId);
        _editable(c);
        final available = (await tx.query(
          'items',
          where: 'collection_id=? AND archived=0',
          whereArgs: [collectionId],
          orderBy: 'id',
        )).map(_item).where((i) => i.enabled).toList();
        if (available.isEmpty) {
          throw const AppFailure('noAvailable', '还没有可用选项，请添加或启用选项');
        }
        CollectionCycle? cycle;
        var candidates = available;
        if (c.drawMode == DrawMode.avoidPrevious && available.length > 1) {
          final last = await tx.query(
            'draw_records',
            columns: ['item_id'],
            where: 'collection_id=?',
            whereArgs: [collectionId],
            orderBy: 'draw_ordinal DESC',
            limit: 1,
          );
          if (last.isNotEmpty) {
            candidates = available
                .where((i) => i.id != last.single['item_id'])
                .toList();
          }
        }
        if (c.drawMode == DrawMode.cycle) {
          cycle =
              await _cycle(tx, collectionId) ??
              await _newCycle(tx, collectionId);
          candidates = available
              .where((i) => !cycle!.consumedItemIds.contains(i.id))
              .toList();
        }
        if (candidates.isEmpty) {
          throw const AppFailure('cycleExhausted', '本轮已抽完，请开启新一轮');
        }
        final fingerprint = jsonEncode([
          c.toJson(),
          candidates.map((i) => i.toJson()).toList(),
          cycle?.id,
        ]);
        final previous = _prepared[requestId];
        if (previous != null && previous.fingerprint != fingerprint) {
          throw const AppFailure('conflict', '集合已变化，请重新抽取');
        }
        final now = _now;
        final selected = previous == null
            ? candidates[_random(candidates.length)]
            : candidates.firstWhere((i) => i.id == previous.record.itemId);
        final record =
            previous?.record ??
            DrawRecord(
              id: requestId,
              collectionId: collectionId,
              itemId: selected.id,
              collectionNameSnapshot: c.name,
              itemTitleSnapshot: selected.title,
              itemNoteSnapshot: selected.note,
              criterionSnapshot: c.executionCriterion,
              modeSnapshot: c.drawMode,
              styleSnapshot: c.presentationStyle,
              cycleId: cycle?.id,
              drawnAt: now,
              updatedAt: now,
            );
        _prepared[requestId] = (fingerprint: fingerprint, record: record);
        final ordinal = (Sqflite.firstIntValue(
          await tx.rawQuery(
            'SELECT COALESCE(MAX(draw_ordinal),0)+1 FROM draw_records',
          ),
        ))!;
        fault?.call('beforeDrawInsert');
        await _insertRecord(tx, record, ordinal);
        fault?.call('afterDrawInsert');
        if (cycle != null) {
          await tx.insert('cycle_consumptions', {
            'cycle_id': cycle.id,
            'collection_id': collectionId,
            'item_id': selected.id,
          });
        }
        fault?.call('afterConsumption');
        return DrawRecord.fromJson(
          record.toJson(),
          ordinal: ordinal,
          appGeneration: generation,
        );
      });
      fault?.call('afterDrawCommit');
      _prepared.remove(requestId);
      return committed;
    } catch (e) {
      if (e is AppFailure) {
        rethrow;
      }
      try {
        final found = await reconcile(requestId);
        if (found != null) {
          return found;
        }
      } catch (_) {
        throw const AppFailure('commitUnknown', '暂时无法确认是否保存，请重试');
      }
      rethrow;
    }
  }

  Future<void> _insertRecord(
    DatabaseExecutor db,
    DrawRecord r,
    int ordinal,
  ) async => db.insert('draw_records', {
    'id': r.id,
    'collection_id': r.collectionId,
    'item_id': r.itemId,
    'cycle_id': r.cycleId,
    'title_snapshot': r.itemTitleSnapshot,
    'completed_at': r.completedAt?.millisecondsSinceEpoch,
    'mode': r.modeSnapshot.name,
    'payload': jsonEncode(r.toJson()),
    'status': r.status.name,
    'drawn_at': r.drawnAt.millisecondsSinceEpoch,
    'draw_ordinal': ordinal,
    'revision': r.revision,
  });
  Future<List<DrawRecord>> history({
    String? collectionId,
    RecordStatus? status,
    String search = '',
    DrawRecord? before,
    int limit = 50,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (collectionId != null) {
      where.add('collection_id=?');
      args.add(collectionId);
    }
    if (status != null) {
      where.add('status=?');
      args.add(status.name);
    }
    if (search.trim().isNotEmpty) {
      where.add("instr(title_snapshot,?)>0");
      args.add(normalized(search));
    }
    if (before != null) {
      where.add('(drawn_at<? OR (drawn_at=? AND draw_ordinal<?))');
      args.addAll([
        before.drawnAt.millisecondsSinceEpoch,
        before.drawnAt.millisecondsSinceEpoch,
        before.drawOrdinal,
      ]);
    }
    return (await _db.query(
      'draw_records',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'drawn_at DESC,draw_ordinal DESC',
      limit: limit,
    )).map(_record).toList();
  }

  Future<DrawRecord> setStatus(String id, RecordStatus status) => _write((
    tx,
  ) async {
    final r = _record(
      (await tx.query('draw_records', where: 'id=?', whereArgs: [id])).single,
    );
    if (r.status == status) {
      return r;
    }
    final m = r.toJson();
    m['status'] = status.name;
    m['completedAt'] = status == RecordStatus.completed
        ? _now.toIso8601String()
        : null;
    m['updatedAt'] = _now.toIso8601String();
    final result = DrawRecord.fromJson(
      m,
      ordinal: r.drawOrdinal,
      revision: r.revision + 1,
      appGeneration: generation,
    );
    await _updateRecord(tx, result);
    return result;
  });
  Future<void> _updateRecord(DatabaseExecutor db, DrawRecord r) async {
    await db.update(
      'draw_records',
      {
        'payload': jsonEncode(r.toJson()),
        'status': r.status.name,
        'completed_at': r.completedAt?.millisecondsSinceEpoch,
        'revision': r.revision,
      },
      where: 'id=?',
      whereArgs: [r.id],
    );
  }

  Future<DrawRecord> undoStatus(
    DrawRecord previous, {
    required int expectedRevision,
  }) => _write((tx) async {
    final rows = await tx.query(
      'draw_records',
      where: 'id=?',
      whereArgs: [previous.id],
    );
    if (previous.appGeneration != generation ||
        rows.isEmpty ||
        rows.single['revision'] != expectedRevision) {
      throw const AppFailure('conflict', '记录已变化，请打开详情修改');
    }
    final m = previous.toJson();
    m['updatedAt'] = _now.toIso8601String();
    final r = DrawRecord.fromJson(
      m,
      ordinal: previous.drawOrdinal,
      revision: expectedRevision + 1,
      appGeneration: generation,
    );
    await _updateRecord(tx, r);
    return r;
  });
  Future<Summary> summary({String? collectionId}) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS total,COALESCE(SUM(status="completed"),0) AS completed,COALESCE(SUM(status="pending"),0) AS pending,COALESCE(SUM(status="skipped"),0) AS skipped FROM draw_records${collectionId == null ? '' : ' WHERE collection_id=?'}',
      collectionId == null ? [] : [collectionId],
    );
    final r = rows.single;
    return Summary(
      total: r['total'] as int,
      completed: r['completed'] as int,
      pending: r['pending'] as int,
      skipped: r['skipped'] as int,
    );
  }

  Future<PickerSettings> settings() async =>
      PickerSettings.fromJson(_payload((await _db.query('settings')).single));
  Future<void> saveSettings(PickerSettings s) => _write((tx) async {
    if (!['system', 'light', 'dark'].contains(s.themeMode)) {
      throw const AppFailure('validation', '请选择可用主题');
    }
    await tx.update('settings', {
      'payload': jsonEncode(s.toJson()),
    }, where: 'id=1');
  });
  Future<void> close() async {
    await _tail;
    await _db.close();
  }

  Future<String> exportBackup() async {
    final result = await _db.transaction((tx) async {
      final collections = (await tx.query(
        'collections',
        orderBy: 'sort_order,id',
      )).map(_payload).toList();
      final items = (await tx.query(
        'items',
        orderBy: 'collection_id,sort_order,id',
      )).map(_payload).toList();
      final records = (await tx.query(
        'draw_records',
        orderBy: 'draw_ordinal',
      )).map(_payload).toList();
      final cycles = <Map<String, dynamic>>[];
      for (final row in await tx.query(
        'cycles',
        orderBy: 'collection_id,sequence',
      )) {
        final m = _payload(row);
        m['consumedItemIds'] = (await tx.query(
          'cycle_consumptions',
          columns: ['item_id'],
          where: 'cycle_id=?',
          whereArgs: [row['id']],
          orderBy: 'item_id',
        )).map((r) => r['item_id']).toList();
        cycles.add(m);
      }
      return jsonEncode({
        'schemaVersion': 1,
        'appVersion': '0.1.0',
        'exportedAt': _now.toIso8601String(),
        'collections': collections,
        'items': items,
        'drawRecords': records,
        'cycles': cycles,
        'settings': _payload((await tx.query('settings')).single),
      });
    });
    if (utf8.encode(result).length > 128 * 1024 * 1024) {
      throw const AppFailure('capacity', '备份超过 128 MiB，请先释放空间或联系开发者');
    }
    return result;
  }

  BackupPreview validateBackup(String input) {
    try {
      if (utf8.encode(input).length > 128 * 1024 * 1024) {
        throw const AppFailure('capacity', '备份超过 128 MiB');
      }
      final m = jsonDecode(input) as Map<String, dynamic>;
      if (m['schemaVersion'] is! int || m['schemaVersion'] != 1) {
        throw const AppFailure('unsupportedVersion', '不支持这份备份的版本');
      }
      if (m['appVersion'] is! String) {
        throw const FormatException();
      }
      final exported = _strictTime(m['exportedAt']);
      final collections = _maps(m['collections']);
      final items = _maps(m['items']);
      final records = _maps(m['drawRecords']);
      final cycles = _maps(m['cycles']);
      final cids = _ids(collections);
      final iids = _ids(items);
      final yids = _ids(cycles);
      _ids(records);
      if (collections.length > 100) {
        throw const FormatException();
      }
      for (final c in collections) {
        _requiredFields(c, [
          'id',
          'name',
          'description',
          'iconKey',
          'colorKey',
          'executionCriterion',
          'drawMode',
          'presentationStyle',
          'sortOrder',
          'archivedAt',
          'createdAt',
          'updatedAt',
        ]);
        checkedText(c['name'] as String, 40, required: true);
        checkedText(c['description'] as String, 200, multiline: true);
        checkedText(c['executionCriterion'] as String, 120, multiline: true);
        if (![
              'dice',
              'movie',
              'book',
              'game',
              'food',
              'walk',
              'music',
              'star',
            ].contains(c['iconKey']) ||
            !['sage', 'lavender', 'sky', 'peach'].contains(c['colorKey'])) {
          throw const FormatException();
        }
        Collection.fromJson(c);
        _orderAndTimes(c);
      }
      final titles = <String>{};
      final itemCounts = <String, int>{};
      final itemMap = {for (final i in items) i['id']: i};
      final cycleMap = {for (final y in cycles) y['id']: y};
      for (final i in items) {
        _requiredFields(i, [
          'id',
          'collectionId',
          'title',
          'note',
          'enabled',
          'archivedAt',
          'sortOrder',
          'createdAt',
          'updatedAt',
        ]);
        if (!cids.contains(i['collectionId']) || i['enabled'] is! bool) {
          throw const FormatException();
        }
        final title = checkedText(i['title'] as String, 100, required: true);
        checkedText(i['note'] as String, 300, multiline: true);
        if (!titles.add(jsonEncode([i['collectionId'], title]))) {
          throw const FormatException();
        }
        final cid = i['collectionId'] as String;
        itemCounts[cid] = (itemCounts[cid] ?? 0) + 1;
        if (itemCounts[cid]! > 1000) {
          throw const FormatException();
        }
        Item.fromJson(i);
        _orderAndTimes(i);
      }
      final sequences = <String>{};
      final consumed = <String>{};
      for (final y in cycles) {
        _requiredFields(y, [
          'id',
          'collectionId',
          'sequence',
          'consumedItemIds',
          'createdAt',
        ]);
        if (!cids.contains(y['collectionId']) ||
            y['sequence'] is! int ||
            (y['sequence'] as int) < 1 ||
            !sequences.add(jsonEncode([y['collectionId'], y['sequence']]))) {
          throw const FormatException();
        }
        _strictTime(y['createdAt']);
        final ids = y['consumedItemIds'] as List;
        final seen = <String>{};
        for (final id in ids) {
          if (id is! String ||
              !seen.add(id) ||
              !iids.contains(id) ||
              itemMap[id]!['collectionId'] != y['collectionId']) {
            throw const FormatException();
          }
          consumed.add(jsonEncode([y['id'], id]));
        }
        CollectionCycle.fromJson(y);
      }
      final recordedConsumptions = <String>{};
      for (final r in records) {
        _requiredFields(r, [
          'id',
          'collectionId',
          'itemId',
          'collectionNameSnapshot',
          'itemTitleSnapshot',
          'itemNoteSnapshot',
          'criterionSnapshot',
          'modeSnapshot',
          'styleSnapshot',
          'cycleId',
          'status',
          'drawnAt',
          'completedAt',
          'updatedAt',
        ]);
        if (!cids.contains(r['collectionId']) ||
            !iids.contains(r['itemId']) ||
            itemMap[r['itemId']]!['collectionId'] != r['collectionId']) {
          throw const FormatException();
        }
        checkedText(r['collectionNameSnapshot'] as String, 40, required: true);
        checkedText(r['itemTitleSnapshot'] as String, 100, required: true);
        checkedText(r['itemNoteSnapshot'] as String, 300, multiline: true);
        checkedText(r['criterionSnapshot'] as String, 120, multiline: true);
        final record = DrawRecord.fromJson(r);
        _strictTime(r['drawnAt']);
        _strictTime(r['updatedAt']);
        if ((record.status == RecordStatus.completed) !=
            (r['completedAt'] != null)) {
          throw const FormatException();
        }
        if (r['completedAt'] != null) {
          _strictTime(r['completedAt']);
        }
        if ((record.modeSnapshot == DrawMode.cycle) !=
            (record.cycleId != null)) {
          throw const FormatException();
        }
        if (record.cycleId != null) {
          if (!yids.contains(record.cycleId) ||
              cycleMap[record.cycleId]!['collectionId'] != r['collectionId']) {
            throw const FormatException();
          }
          final key = jsonEncode([record.cycleId, record.itemId]);
          if (!consumed.contains(key) || !recordedConsumptions.add(key)) {
            throw const FormatException();
          }
        }
      }
      if (recordedConsumptions.length != consumed.length) {
        throw const FormatException();
      }
      final settingsMap = m['settings'] as Map<String, dynamic>;
      _requiredFields(settingsMap, [
        'themeMode',
        'soundEnabled',
        'hapticsEnabled',
        'reduceMotion',
      ]);
      if (!['system', 'light', 'dark'].contains(settingsMap['themeMode'])) {
        throw const FormatException();
      }
      for (final key in ['soundEnabled', 'hapticsEnabled', 'reduceMotion']) {
        if (settingsMap[key] is! bool) {
          throw const FormatException();
        }
      }
      if (settingsMap.containsKey('redrawHintSeen') &&
          settingsMap['redrawHintSeen'] is! bool) {
        throw const FormatException();
      }
      PickerSettings.fromJson(settingsMap);
      return BackupPreview.validated(
        jsonEncode(m),
        exported,
        collections.length,
        items.length,
        records.length,
      );
    } on AppFailure {
      rethrow;
    } catch (_) {
      throw const AppFailure('backupInvalid', '备份内容不完整或数据关系无效，未更改现有数据');
    }
  }

  void _requiredFields(Map<String, dynamic> m, List<String> names) {
    if (!names.every(m.containsKey)) {
      throw const FormatException();
    }
  }

  List<Map<String, dynamic>> _maps(dynamic raw) =>
      (raw as List).map((e) => e as Map<String, dynamic>).toList();
  Set<String> _ids(List<Map<String, dynamic>> rows) {
    final ids = <String>{};
    for (final r in rows) {
      if (r['id'] is! String ||
          (r['id'] as String).trim().isEmpty ||
          !ids.add(r['id'])) {
        throw const FormatException();
      }
    }
    return ids;
  }

  void _orderAndTimes(Map<String, dynamic> m) {
    if (m['sortOrder'] is! int || (m['sortOrder'] as int) < 0) {
      throw const FormatException();
    }
    _strictTime(m['createdAt']);
    _strictTime(m['updatedAt']);
    if (m['archivedAt'] != null) {
      _strictTime(m['archivedAt']);
    }
  }

  DateTime _strictTime(dynamic input) {
    if (input is! String) {
      throw const FormatException();
    }
    final match = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$',
    ).firstMatch(input);
    if (match == null) {
      throw const FormatException();
    }
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final probe = DateTime.utc(year, month, day);
    if (probe.year != year ||
        probe.month != month ||
        probe.day != day ||
        int.parse(match[4]!) > 23 ||
        int.parse(match[5]!) > 59 ||
        int.parse(match[6]!) > 59) {
      throw const FormatException();
    }
    final zone = match[7]!;
    if (zone != 'Z' &&
        (int.parse(zone.substring(1, 3)) > 23 ||
            int.parse(zone.substring(4)) > 59)) {
      throw const FormatException();
    }
    return DateTime.fromMillisecondsSinceEpoch(
      DateTime.parse(input).toUtc().millisecondsSinceEpoch,
      isUtc: true,
    );
  }

  Future<void> _deleteAll(DatabaseExecutor tx) async {
    for (final table in [
      'cycle_consumptions',
      'draw_records',
      'cycles',
      'items',
      'collections',
      'settings',
    ]) {
      await tx.delete(table);
    }
  }

  Future<void> restoreBackup(BackupPreview preview) async {
    final checked = validateBackup(preview.json);
    final m = jsonDecode(checked.json) as Map<String, dynamic>;
    await _write((tx) async {
      await _deleteAll(tx);
      fault?.call('restoreAfterDelete');
      for (final c in _maps(m['collections'])) {
        await _putCollection(tx, Collection.fromJson(c), insert: true);
      }
      for (final i in _maps(m['items'])) {
        await _putItem(tx, Item.fromJson(i), insert: true);
      }
      for (final y in _maps(m['cycles'])) {
        final cycle = CollectionCycle.fromJson(y);
        await tx.insert('cycles', {
          'id': cycle.id,
          'collection_id': cycle.collectionId,
          'sequence': cycle.sequence,
          'payload': jsonEncode(cycle.toJson()),
        });
        for (final id in cycle.consumedItemIds) {
          await tx.insert('cycle_consumptions', {
            'cycle_id': cycle.id,
            'collection_id': cycle.collectionId,
            'item_id': id,
          });
        }
      }
      fault?.call('restoreHalfway');
      var ordinal = 0;
      for (final r in _maps(m['drawRecords'])) {
        await _insertRecord(tx, DrawRecord.fromJson(r), ++ordinal);
      }
      await tx.insert('settings', {
        'id': 1,
        'payload': jsonEncode(PickerSettings.fromJson(m['settings']).toJson()),
      });
    }, replacesData: true);
  }

  Future<void> clear() async {
    await _write((tx) async {
      await _deleteAll(tx);
      fault?.call('clearAfterDelete');
      await tx.insert('settings', {
        'id': 1,
        'payload': jsonEncode(const PickerSettings().toJson()),
      });
    }, replacesData: true);
  }
}
