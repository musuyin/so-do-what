import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:so_do_what/core/data/picker_store.dart';

void main() {
  late PickerStore store;
  String? fail;
  var randomCalls = 0;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    fail = null;
    randomCalls = 0;
    store = await PickerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      randomIndex: (n) {
        randomCalls++;
        return 0;
      },
      fault: (stage) {
        if (stage == fail) throw StateError('injected');
      },
    );
  });
  tearDown(() async => store.close());
  Future<Collection> collection({
    DrawMode mode = DrawMode.allowRepeat,
    String items = '甲\n乙\n丙',
  }) => store.saveCollection(name: '周末小事', drawMode: mode, initialItems: items);
  Future<DrawRecord> draw(Collection c, [String? id]) =>
      store.draw(c.id, requestId: id ?? store.newId());

  test('A01/A02 NFC batch classifications and atomic validation', () async {
    final c = await collection(items: 'é\nA\na');
    final preview = await store.previewImport(c.id, 'e\u0301\n\n新选项\n新选项');
    expect(preview.added, 1);
    expect(preview.duplicates, 2);
    expect(preview.blank, 1);
    await store.importItems(c.id, 'e\u0301\n新选项');
    expect((await store.listItems(c.id)).length, 4);
    await expectLater(
      store.saveCollection(name: '失败集合', initialItems: '正常\n${'长' * 101}'),
      throwsA(isA<AppFailure>()),
    );
    expect((await store.listCollections()).length, 1);
    expect(checkedText('👨‍👩‍👧‍👦', 1, required: true), '👨‍👩‍👧‍👦');
  });
  test('A03 empty pool never samples or records', () async {
    final c = await collection(items: '');
    await expectLater(draw(c), throwsA(isA<AppFailure>()));
    expect(randomCalls, 0);
    expect((await store.summary()).total, 0);
  });
  test('A04 repeat allowed and request idempotency', () async {
    final c = await collection();
    final a = await draw(c, 'request');
    final same = await draw(c, 'request');
    final b = await draw(c);
    expect(a.id, same.id);
    expect(a.itemId, b.itemId);
    expect(randomCalls, 2);
    expect((await store.summary()).total, 2);
  });
  test(
    'A05/A06 previous successful record across modes and single item',
    () async {
      var c = await collection();
      final a = await draw(c);
      c = await store.saveCollection(
        id: c.id,
        name: c.name,
        drawMode: DrawMode.avoidPrevious,
      );
      final b = await draw(c);
      expect(a.itemId, isNot(b.itemId));
      final single = await collection(
        mode: DrawMode.avoidPrevious,
        items: '唯一',
      );
      expect((await draw(single)).itemId, (await draw(single)).itemId);
    },
  );
  test('A07/A08/A09/A10 cycle consumption survives status, editing and mode switch', () async {
    var c = await collection(mode: DrawMode.cycle);
    final a = await draw(c);
    final cycle = await store.currentCycle(c.id);
    await store.setStatus(a.id, RecordStatus.completed);
    await store.setStatus(a.id, RecordStatus.skipped);
    await store.archiveItem(a.itemId, true);
    await store.archiveItem(a.itemId, false);
    c = await store.saveCollection(
      id: c.id,
      name: c.name,
      drawMode: DrawMode.allowRepeat,
    );
    await draw(c);
    c = await store.saveCollection(
      id: c.id,
      name: c.name,
      drawMode: DrawMode.cycle,
    );
    final b = await draw(c);
    final d = await draw(c);
    expect({a.itemId, b.itemId, d.itemId}.length, 3);
    await expectLater(draw(c), throwsA(isA<AppFailure>()));
    expect((await store.currentCycle(c.id))!.id, cycle!.id);
    await store.saveItem(collectionId: c.id, title: '新增');
    await draw(c);
    final next = await store.startNextCycle(c.id, expectedCycleId: cycle.id);
    final repeated = await store.startNextCycle(
      c.id,
      expectedCycleId: cycle.id,
    );
    expect(next.id, repeated.id);
    expect(next.sequence, 2);
    await draw(c);
  });
  for (final stage in [
    'beforeDrawInsert',
    'afterDrawInsert',
    'afterConsumption',
  ]) {
    test('A12 $stage rollback keeps result for retry', () async {
      final c = await collection(mode: DrawMode.cycle);
      fail = stage;
      await expectLater(draw(c, 'retry'), throwsStateError);
      expect((await store.summary()).total, 0);
      expect((await store.currentCycle(c.id))!.consumedItemIds, isEmpty);
      fail = null;
      await draw(c, 'retry');
      expect(randomCalls, 1);
      expect((await store.summary()).total, 1);
      expect((await store.currentCycle(c.id))!.consumedItemIds.length, 1);
    });
  }
  test('A12 unknown commit reconciles same record', () async {
    final c = await collection(mode: DrawMode.cycle);
    fail = 'afterDrawCommit';
    final r = await draw(c, 'unknown');
    expect(r.id, 'unknown');
    expect((await store.summary()).total, 1);
    expect(randomCalls, 1);
  });
  test('A14/A15 redraw preserves original and all nine status transitions are idempotent', () async {
    final c = await collection();
    final a = await draw(c);
    await draw(c);
    expect((await store.reconcile(a.id))!.status, RecordStatus.pending);
    for (final from in RecordStatus.values) {
      for (final to in RecordStatus.values) {
        await store.setStatus(a.id, from);
        final changed = await store.setStatus(a.id, to);
        final same = await store.setStatus(a.id, to);
        expect(same.revision, changed.revision);
        expect(same.updatedAt, changed.updatedAt);
        expect(same.completedAt, changed.completedAt);
        expect(same.completedAt != null, to == RecordStatus.completed);
      }
    }
    final previous = (await store.reconcile(a.id))!;
    final changed = await store.setStatus(a.id, RecordStatus.completed);
    await store.undoStatus(previous, expectedRevision: changed.revision);
    await expectLater(
      store.undoStatus(previous, expectedRevision: changed.revision),
      throwsA(isA<AppFailure>()),
    );
  });
  test(
    'A16/A17/A18 raw counts and immutable snapshots include archives',
    () async {
      expect((await store.summary()).rate, null);
      final a = await collection();
      final b = await collection(items: '单项');
      for (var n = 0; n < 10; n++) {
        final r = await draw(a);
        if (n < 2) await store.setStatus(r.id, RecordStatus.completed);
      }
      final last = await draw(b);
      await store.setStatus(last.id, RecordStatus.completed);
      expect((await store.summary()).rateLabel, '27.3%');
      final first = (await store.history(collectionId: a.id)).first;
      await store.saveCollection(
        id: a.id,
        name: '新名字',
        executionCriterion: '新标准',
      );
      await store.saveItem(id: first.itemId, collectionId: a.id, title: '新标题');
      await store.archiveCollection(a.id, true);
      expect((await store.reconcile(first.id))!.collectionNameSnapshot, a.name);
      expect(
        (await store.reconcile(first.id))!.itemTitleSnapshot,
        first.itemTitleSnapshot,
      );
      expect((await store.summary()).total, 11);
      await store.setStatus(first.id, RecordStatus.skipped);
    },
  );
  test('history cursor 50/page and literal title search', () async {
    final c = await collection(items: '百分号%_');
    for (var n = 0; n < 55; n++) {
      await draw(c);
    }
    final first = await store.history();
    final second = await store.history(before: first.last);
    expect(first.length, 50);
    expect(second.length, 5);
    expect({...first.map((r) => r.id), ...second.map((r) => r.id)}.length, 55);
    expect((await store.history(search: '%_', limit: 100)).length, 55);
    expect(await store.history(search: '不存在'), isEmpty);
  });
  test(
    'A19 complete backup roundtrip preserves cycle settings archive and status',
    () async {
      final c = await collection(mode: DrawMode.cycle);
      final r = await draw(c);
      await store.setStatus(r.id, RecordStatus.completed);
      await store.archiveItem(r.itemId, true);
      await store.saveSettings(
        const PickerSettings(
          themeMode: 'dark',
          soundEnabled: true,
          reduceMotion: true,
        ),
      );
      final original = jsonDecode(await store.exportBackup()) as Map;
      final validated = store.validateBackup(jsonEncode(original));
      await store.clear();
      await store.restoreBackup(validated);
      final restored = jsonDecode(await store.exportBackup()) as Map;
      original.remove('exportedAt');
      restored.remove('exportedAt');
      expect(restored, original);
      expect((await store.currentCycle(c.id))!.consumedItemIds, {r.itemId});
    },
  );
  for (final stage in [
    'restoreAfterDelete',
    'restoreHalfway',
    'clearAfterDelete',
  ]) {
    test('A20 $stage failure leaves all old entities intact', () async {
      final c = await collection(mode: DrawMode.cycle);
      await draw(c);
      final before = jsonDecode(await store.exportBackup()) as Map;
      final token = store.validateBackup(jsonEncode(before));
      fail = stage;
      await expectLater(
        stage.startsWith('clear') ? store.clear() : store.restoreBackup(token),
        throwsStateError,
      );
      fail = null;
      final after = jsonDecode(await store.exportBackup()) as Map;
      before.remove('exportedAt');
      after.remove('exportedAt');
      expect(after, before);
    });
  }
  test('A20 rejects invalid schema IDs dates enums and relationships without writing', () async {
    final c = await collection(mode: DrawMode.cycle);
    await draw(c);
    final raw = await store.exportBackup();
    final mutations = <void Function(Map<String, dynamic>)>[
      (m) => m['schemaVersion'] = 2,
      (m) => m['collections'][0]['createdAt'] = '2026-02-30T00:00:00Z',
      (m) => m['items'][0]['collectionId'] = 'missing',
      (m) => m['items'].add(m['items'][0]),
      (m) => m['cycles'][0]['consumedItemIds'] = [],
      (m) => m['drawRecords'][0]['status'] = 'wrong',
      (m) => m['drawRecords'][0]['completedAt'] = '2026-01-01T00:00:00Z',
      (m) => m['collections'][0]['colorKey'] = 'unknown',
    ];
    for (final mutation in mutations) {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      mutation(m);
      expect(
        () => store.validateBackup(jsonEncode(m)),
        throwsA(isA<AppFailure>()),
      );
    }
    expect((await store.summary()).total, 1);
  });
  test(
    'A13 persisted records and cycle reopen from actual SQLite file',
    () async {
      final dir = await Directory.systemTemp.createTemp('picker_test');
      final path = '${dir.path}/picker.db';
      var fileStore = await PickerStore.open(
        path: path,
        factory: databaseFactoryFfi,
        randomIndex: (n) => 0,
      );
      final c = await fileStore.saveCollection(
        name: '持久化',
        drawMode: DrawMode.cycle,
        initialItems: '甲\n乙',
      );
      final r = await fileStore.draw(c.id, requestId: 'persisted');
      await fileStore.close();
      fileStore = await PickerStore.open(
        path: path,
        factory: databaseFactoryFfi,
      );
      expect((await fileStore.history()).single.id, r.id);
      expect((await fileStore.currentCycle(c.id))!.consumedItemIds, {r.itemId});
      await fileStore.close();
      await dir.delete(recursive: true);
    },
  );
  test(
    'capacity includes archived collections/items and batch line boundary',
    () async {
      final c = await collection(items: '');
      await expectLater(
        store.previewImport(c.id, List.filled(501, '甲').join('\n')),
        throwsA(isA<AppFailure>()),
      );
      await store.importItems(
        c.id,
        List.generate(500, (n) => '选项$n').join('\n'),
      );
      await store.importItems(
        c.id,
        List.generate(500, (n) => '选项${n + 500}').join('\n'),
      );
      final first = (await store.listItems(c.id)).first;
      await store.archiveItem(first.id, true);
      await expectLater(
        store.saveItem(collectionId: c.id, title: '超限'),
        throwsA(isA<AppFailure>()),
      );
      for (var n = 1; n < 100; n++) {
        await store.saveCollection(name: '集合$n');
      }
      await store.archiveCollection(c.id, true);
      await expectLater(
        store.saveCollection(name: '超限'),
        throwsA(isA<AppFailure>()),
      );
    },
  );
  test(
    'sorting full scope preserves IDs and archive/disabled semantics',
    () async {
      final c = await collection();
      final items = await store.listItems(c.id);
      final first = items.first;
      await store.saveItem(
        id: first.id,
        collectionId: c.id,
        title: first.title,
        enabled: false,
      );
      await store.archiveItem(first.id, true);
      await store.archiveItem(first.id, false);
      expect((await store.listItems(c.id)).first.enabled, false);
      await store.reorderItems(c.id, items.reversed.map((e) => e.id).toList());
      expect(
        (await store.listItems(c.id)).map((e) => e.id),
        items.reversed.map((e) => e.id),
      );
      await expectLater(
        store.reorderItems(c.id, [first.id]),
        throwsA(isA<AppFailure>()),
      );
    },
  );
  test(
    'restore invalidates previous undo handles even when revision repeats',
    () async {
      final c = await collection();
      final old = await draw(c);
      await store.setStatus(old.id, RecordStatus.completed);
      final token = store.validateBackup(await store.exportBackup());
      await store.restoreBackup(token);
      await expectLater(
        store.undoStatus(old, expectedRevision: 0),
        throwsA(isA<AppFailure>()),
      );
      final current = (await store.history()).single;
      final next = await store.setStatus(current.id, RecordStatus.skipped);
      await store.undoStatus(current, expectedRevision: next.revision);
      expect(
        (await store.reconcile(current.id))!.status,
        RecordStatus.completed,
      );
    },
  );
  test('queued pre-restore command cannot modify replacement data', () async {
    final c = await collection();
    final token = store.validateBackup(await store.exportBackup());
    final restoring = store.restoreBackup(token);
    final stale = store.saveItem(collectionId: c.id, title: '旧页面提交');
    final assertion = expectLater(stale, throwsA(isA<AppFailure>()));
    await restoring;
    await assertion;
    expect(
      (await store.listItems(c.id)).where((i) => i.title == '旧页面提交'),
      isEmpty,
    );
  });
  test('newer SQLite schema refuses downgrade and preserves file', () async {
    final dir = await Directory.systemTemp.createTemp('picker_newer');
    final path = '${dir.path}/newer.db';
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, v) => db.execute('CREATE TABLE future_data(value TEXT)'),
      ),
    );
    await db.insert('future_data', {'value': 'fictional'});
    await db.close();
    await expectLater(
      PickerStore.open(path: path, factory: databaseFactoryFfi),
      throwsA(isA<AppFailure>()),
    );
    final again = await databaseFactoryFfi.openDatabase(path);
    expect((await again.query('future_data')).single['value'], 'fictional');
    await again.close();
    await dir.delete(recursive: true);
  });
}
