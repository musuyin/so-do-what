import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:so_do_what/core/data/picker_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('100 collections, 100k items and 20001 histories survive atomic backup restore', () async {
    final store = await PickerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(store.close);
    final c = await store.saveCollection(name: '虚构容量集合', initialItems: '虚构选项');
    await store.draw(c.id, requestId: 'fixture-seed');
    final envelope =
        jsonDecode(await store.exportBackup()) as Map<String, dynamic>;
    final collection =
        (envelope['collections'] as List).single as Map<String, dynamic>;
    final item = (envelope['items'] as List).single as Map<String, dynamic>;
    final record =
        (envelope['drawRecords'] as List).single as Map<String, dynamic>;
    envelope['collections'] = List.generate(
      100,
      (n) => {
        ...collection,
        'id': 'collection-$n',
        'name': '虚构容量集合 $n',
        'sortOrder': n,
      },
    );
    envelope['items'] = [
      for (var c = 0; c < 100; c++)
        for (var i = 0; i < 1000; i++)
          {
            ...item,
            'id': 'item-$c-$i',
            'collectionId': 'collection-$c',
            'title': '虚构选项 $i',
            'sortOrder': i,
          },
    ];
    envelope['drawRecords'] = List.generate(
      20001,
      (n) => {
        ...record,
        'id': 'record-$n',
        'collectionId': 'collection-0',
        'itemId': 'item-0-0',
      },
    );
    final source = jsonEncode(envelope);
    final watch = Stopwatch()..start();
    final preview = store.validateBackup(source);
    await store.restoreBackup(preview);
    final importMs = watch.elapsedMilliseconds;
    expect((await store.listCollections()).length, 100);
    expect((await store.listItems('collection-99')).length, 1000);
    expect((await store.summary()).total, 20001);
    final first = await store.history();
    final second = await store.history(before: first.last);
    expect(first.length, 50);
    expect(second.length, 50);
    expect(
      first
          .map((r) => r.id)
          .toSet()
          .intersection(second.map((r) => r.id).toSet()),
      isEmpty,
    );
    final exported = await store.exportBackup();
    final restored = store.validateBackup(exported);
    expect(restored.itemCount, 100000);
    expect(restored.recordCount, 20001);
    // A new successful draw beyond the baseline is never silently truncated.
    await store.draw('collection-0', requestId: 'after-baseline');
    expect((await store.summary()).total, 20002);
    // ignore: avoid_print
    print(
      'CAPACITY: bytes=${utf8.encode(source).length}, importMs=$importMs, roundTripMs=${watch.elapsedMilliseconds}',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
