import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:so_do_what/app/app.dart';
import 'package:so_do_what/core/data/picker_store.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android SQLite offline round trip and real app navigation', (
    tester,
  ) async {
    final path = p.join(await getDatabasesPath(), 'offline_acceptance.db');
    await deleteDatabase(path);
    var store = await PickerStore.open(path: path, randomIndex: (_) => 0);
    final collection = await store.saveCollection(
      name: '周末小事',
      initialItems: '散步十分钟\n整理书桌\n听一首歌',
      drawMode: DrawMode.cycle,
    );
    final first = await store.draw(collection.id, requestId: 'android-1');
    final duplicate = await store.draw(collection.id, requestId: 'android-1');
    expect(first.id, duplicate.id);
    await store.close();
    store = await PickerStore.open(path: path, randomIndex: (_) => 0);
    expect(
      (await store.currentCycle(collection.id))!.consumedItemIds.length,
      1,
    );
    expect((await store.summary()).total, 1);
    await store.setStatus(first.id, RecordStatus.completed);
    final backup = await store.exportBackup();
    await store.clear();
    expect((await store.summary()).total, 0);
    await store.restoreBackup(store.validateBackup(backup));
    expect((await store.summary()).rateLabel, '100.0%');
    final next = await store.draw(collection.id, requestId: 'android-2');
    expect(next.itemId, isNot(first.itemId));
    await tester.pumpWidget(PickerApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('周末小事'), findsWidgets);
    await tester.tap(find.text('记录').last);
    await tester.pumpAndSettle();
    expect(find.text(first.itemTitleSnapshot), findsWidgets);
    await tester.tap(find.text('回顾').last);
    await tester.pumpAndSettle();
    expect(find.text('50.0%'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await store.close();
    await deleteDatabase(path);
  });
}
