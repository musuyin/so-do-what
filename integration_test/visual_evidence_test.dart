import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:so_do_what/app/app.dart';
import 'package:so_do_what/app/ui.dart';
import 'package:so_do_what/core/data/picker_store.dart';
import 'package:so_do_what/features/collections/collection_editor_page.dart';
import 'package:so_do_what/features/drawing/collection_draw_page.dart';
import 'package:so_do_what/features/drawing/record_result_page.dart';
import 'package:so_do_what/features/history/history_page.dart';
import 'package:so_do_what/features/items/items_page.dart';
import 'package:so_do_what/features/review/review_page.dart';
import 'package:so_do_what/features/settings/settings_page.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Capture implemented screens on Android', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    final path = p.join(await getDatabasesPath(), 'visual_acceptance.db');
    await deleteDatabase(path);
    final store = await PickerStore.open(path: path, randomIndex: (_) => 0);
    final c = await store.saveCollection(
      name: '给周末留一点空白',
      description: '一些轻轻松松、想起来就能做的小事。',
      initialItems: '去公园走一走\n看一部收藏的电影\n给自己做一顿饭',
      executionCriterion: '放下别的事情，认真享受这段时间',
    );
    final r = await store.draw(c.id, requestId: 'visual-1');
    final directory = Directory(p.join(p.dirname(path), 'evidence'));
    await directory.create(recursive: true);
    Future<void> capture(String name, Widget page, {bool dark = false}) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: pickerTheme(dark ? Brightness.dark : Brightness.light),
            home: page,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: name);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(p.join(directory.path, '$name.png'))
          .writeAsBytes(data!.buffer.asUint8List());
      // ignore: avoid_print
      print('EVIDENCE:$name:${base64Encode(data.buffer.asUint8List())}');
      image.dispose();
    }

    await capture('01-home', PickerApp(store: store));
    await capture(
      '02-collection',
      CollectionDrawPage(store: store, collectionId: c.id),
    );
    await capture('03-result', RecordResultPage(store: store, record: r));
    await capture('04-items', ItemsPage(store: store, collection: c));
    await capture(
      '05-editor',
      CollectionEditorPage(store: store, collection: c),
    );
    await capture('06-history', HistoryPage(store: store));
    await capture('07-review', ReviewPage(store: store));
    await capture(
      '08-settings',
      SettingsPage(store: store, onSettingsChanged: () {}, onReset: () {}),
    );
    await capture(
      '09-collection-dark',
      CollectionDrawPage(store: store, collectionId: c.id),
      dark: true,
    );
    await capture('10-review-dark', ReviewPage(store: store), dark: true);
    await tester.pumpWidget(const SizedBox.shrink());
    await store.close();
  });
}
