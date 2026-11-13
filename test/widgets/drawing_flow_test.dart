import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:so_do_what/core/data/picker_store.dart';
import 'package:so_do_what/features/drawing/collection_draw_page.dart';

Future<void> drain(WidgetTester tester, {int frames = 24}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<T> readWithPump<T>(
  WidgetTester tester,
  Future<T> Function() read,
) async {
  var completed = false;
  T? result;
  Object? failure;
  read().then(
    (value) {
      result = value;
      completed = true;
    },
    onError: (Object e) {
      failure = e;
      completed = true;
    },
  );
  for (var i = 0; !completed && i < 100; i++) {
    await drain(tester, frames: 1);
  }
  if (failure != null) throw failure!;
  if (!completed) throw StateError('Database callback did not complete');
  return result as T;
}

void main() {
  setUpAll(sqfliteFfiInit);
  late PickerStore store;
  Future<void> init(WidgetTester tester) async {
    await tester.runAsync(() async {
      store = await PickerStore.open(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
        randomIndex: (_) => 0,
      );
      await store.saveSettings(const PickerSettings(hapticsEnabled: false));
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await drain(tester, frames: 5);
      await readWithPump(tester, () => store.close());
    });
  }

  testWidgets(
    'double tap saves once before animation; redraw preserves old record',
    (tester) async {
      await init(tester);
      final c = await tester.runAsync(
        () => store.saveCollection(name: '周末小事', initialItems: '散步十分钟\n整理书桌'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionDrawPage(store: store, collectionId: c!.id),
        ),
      );
      await drain(tester);
      final button = find.text('抽一个');
      await tester.tap(button);
      await tester.tap(button);
      for (var i = 0; i < 40 && find.text('跳过动画').evaluate().isEmpty; i++) {
        await drain(tester, frames: 1);
      }
      expect(find.text('跳过动画'), findsOneWidget);
      expect(find.text('跳过动画'), findsOneWidget);
      expect((await readWithPump(tester, () => store.summary())).total, 1);
      await tester.tap(find.text('跳过动画'));
      await drain(tester);
      expect(find.text('已加入待行动'), findsOneWidget);
      final first = (await readWithPump(tester, () => store.history())).single;
      await tester.ensureVisible(find.text('再抽一次'));
      await tester.tap(find.text('再抽一次'));
      await drain(tester);
      expect(find.textContaining('再抽会新增一条记录'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '再抽一次'));
      for (var i = 0; i < 40 && find.text('跳过动画').evaluate().isEmpty; i++) {
        await drain(tester, frames: 1);
      }
      expect(find.text('跳过动画'), findsOneWidget);
      expect((await readWithPump(tester, () => store.summary())).total, 2);
      expect(
        (await readWithPump(tester, () => store.reconcile(first.id)))!.status,
        RecordStatus.pending,
      );
    },
  );
  testWidgets(
    'empty collection never saves a draw and offers option management',
    (tester) async {
      await init(tester);
      final c = await tester.runAsync(() => store.saveCollection(name: '空集合'));
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionDrawPage(store: store, collectionId: c!.id),
        ),
      );
      await drain(tester);
      expect(find.text('添加 / 启用选项'), findsOneWidget);
      expect(find.text('抽一个'), findsNothing);
      expect((await readWithPump(tester, () => store.summary())).total, 0);
    },
  );
  testWidgets(
    'cycle exhaustion requires an explicit new round without drawing',
    (tester) async {
      await init(tester);
      final c = await tester.runAsync(
        () => store.saveCollection(
          name: '一件小事',
          initialItems: '整理书桌',
          drawMode: DrawMode.cycle,
        ),
      );
      await tester.runAsync(() => store.draw(c!.id, requestId: 'first'));
      await tester.pumpWidget(
        MaterialApp(
          home: CollectionDrawPage(store: store, collectionId: c!.id),
        ),
      );
      await drain(tester);
      expect(find.text('本轮已抽完'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '开启新一轮'));
      await drain(tester);
      expect(find.text('本轮还剩 1 / 1 个可抽'), findsOneWidget);
      expect((await readWithPump(tester, () => store.summary())).total, 1);
    },
  );
}
