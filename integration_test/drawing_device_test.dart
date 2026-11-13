import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:so_do_what/app/ui.dart';
import 'package:so_do_what/core/data/picker_store.dart';
import 'package:so_do_what/features/drawing/collection_draw_page.dart';
import 'package:so_do_what/features/drawing/record_result_page.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Complete gacha on Android with committed result and status', (
    tester,
  ) async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    final path = p.join(await getDatabasesPath(), 'recording_acceptance.db');
    await deleteDatabase(path);
    final store = await PickerStore.open(path: path, randomIndex: (_) => 0);
    final c = await store.saveCollection(
      name: '周末，做一点喜欢的事',
      initialItems: '去公园走一走\n看一部收藏的电影\n给自己做一顿饭',
    );
    await store.saveSettings(const PickerSettings(hapticsEnabled: false));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: pickerTheme(Brightness.light),
        home: CollectionDrawPage(store: store, collectionId: c.id),
      ),
    );
    await tester.pumpAndSettle();
    // The external recorder waits for this marker; no business timing depends on it.
    // ignore: avoid_print
    print('RECORDING_READY');
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 4)),
    );
    await tester.scrollUntilVisible(find.text('抽一个'), 200);
    await tester.tap(find.text('抽一个'));
    for (
      var i = 0;
      i < 100 && find.byType(RecordResultPage).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('已加入待行动'), 100);
    expect(find.text('已加入待行动'), findsOneWidget);
    expect((await store.summary()).total, 1);
    await tester.scrollUntilVisible(find.text('我做过了'), 200);
    await tester.tap(find.text('我做过了'));
    await tester.pumpAndSettle();
    expect((await store.summary()).completed, 1);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 5)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await store.close();
    await SystemChrome.setPreferredOrientations([]);
  });
}
