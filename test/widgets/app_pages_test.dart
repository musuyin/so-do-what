import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:so_do_what/core/data/picker_store.dart';
import 'package:so_do_what/app/app.dart';
import 'package:so_do_what/app/ui.dart';
import 'package:so_do_what/features/collections/collection_editor_page.dart';
import 'package:so_do_what/features/history/history_page.dart';
import 'package:so_do_what/features/review/review_page.dart';
import 'package:so_do_what/features/items/items_page.dart';
import 'package:so_do_what/features/settings/settings_page.dart';

void main() {
  late PickerStore store;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    var nextId = 97;
    store = await PickerStore.open(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
      newId: () => String.fromCharCode(nextId++),
    );
  });
  tearDown(() async {
    await store.close();
  });
  testWidgets('空库启动与三个入口可访问，没有伪造数据', (tester) async {
    await tester.pumpWidget(PickerApp(store: store));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('创建第一个集合'), findsOneWidget);
    expect(find.text('体验一下'), findsOneWidget);
    expect(await tester.runAsync(() => store.history()), isEmpty);
    await tester.tap(find.text('记录').last);
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('抽出的结果会留在这里'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('编辑后返回确认，取消放弃保留输入', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  openPage(context, CollectionEditorPage(store: store)),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, '周末的小事');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('放弃这次修改？'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('周末的小事'), findsOneWidget);
    expect(await tester.runAsync(() => store.listCollections()), isEmpty);
  });
  for (final dark in [false, true]) {
    testWidgets('360宽200%字号表单、历史和回顾可滚动 ${dark ? '深色' : '浅色'}', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = (await tester.runAsync(
        () => store.saveCollection(
          name: '这是一段用于验证完整显示与滚动操作的集合名称',
          initialItems: '散步十分钟\n读一页书',
        ),
      ))!;
      Future<void> show(Widget page) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: pickerTheme(dark ? Brightness.dark : Brightness.light),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(360, 800),
                textScaler: TextScaler.linear(2),
              ),
              child: page,
            ),
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await show(CollectionEditorPage(store: store, collection: c));
      await tester.drag(find.byType(ListView), const Offset(0, -1600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await show(HistoryPage(store: store, collectionId: c.id));
      await show(ItemsPage(store: store, collection: c));
      await show(
        SettingsPage(store: store, onSettingsChanged: () {}, onReset: () {}),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -1400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await show(ReviewPage(store: store));
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
