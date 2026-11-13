import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:so_do_what/app/ui.dart';
import 'package:so_do_what/core/data/picker_store.dart';
import 'package:so_do_what/features/settings/settings_page.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android system documents save, cancel and restore', (
    tester,
  ) async {
    final path = p.join(await getDatabasesPath(), 'documents_acceptance.db');
    await deleteDatabase(path);
    final store = await PickerStore.open(path: path);
    final c = await store.saveCollection(
      name: '虚构文件备份集合',
      initialItems: '散步\n读书',
    );
    await store.draw(c.id, requestId: 'documents-draw');
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: pickerTheme(Brightness.light),
        home: SettingsPage(
          store: store,
          onSettingsChanged: () {},
          onReset: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> waitFor(String text) async {
      for (var i = 0; i < 300 && find.text(text).evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text(text), findsWidgets);
    }

    await tester.scrollUntilVisible(find.text('导出完整备份'), 200);
    await tester.tap(find.text('导出完整备份'));
    // ignore: avoid_print
    print('NATIVE_SAVE_OPEN');
    await waitFor('备份已保存');
    expect((await store.summary()).total, 1);
    await store.saveCollection(name: '恢复后应被替换的虚构集合');
    await tester.tap(find.text('从备份覆盖恢复'));
    // ignore: avoid_print
    print('NATIVE_RESTORE_OPEN');
    await waitFor('替换并恢复');
    await tester.tap(find.text('替换并恢复'));
    for (
      var i = 0;
      i < 100 && (await store.listCollections()).length != 1;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect((await store.listCollections()).length, 1);
    expect((await store.summary()).total, 1);
    await tester.tap(find.text('导出完整备份'));
    // ignore: avoid_print
    print('NATIVE_CANCEL_OPEN');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 6)),
    );
    await tester.pumpAndSettle();
    expect((await store.summary()).total, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await store.close();
  }, skip: !const bool.fromEnvironment('NATIVE_DOCUMENTS_AUTOMATION'));
}
