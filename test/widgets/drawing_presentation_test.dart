import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_do_what/core/domain/models.dart';
import 'package:so_do_what/features/drawing/demo_page.dart';
import 'package:so_do_what/features/drawing/gacha_machine.dart';
import 'package:so_do_what/features/drawing/gacha_presentation.dart';

void main() {
  final time = DateTime.utc(2026, 11, 13);
  final record = DrawRecord(
    id: 'committed',
    collectionId: 'c',
    itemId: 'i',
    collectionNameSnapshot: '周末小事',
    itemTitleSnapshot: '散步十分钟',
    drawnAt: time,
    updatedAt: time,
  );
  const settings = PickerSettings(hapticsEnabled: false);

  testWidgets(
    'full presentation and skip reveal the same saved result only once',
    (tester) async {
      var reveals = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: GachaPresentation(
            record: record,
            settings: settings,
            onReveal: () {
              reveals++;
            },
          ),
        ),
      );
      expect(reveals, 0);
      await tester.pump(const Duration(milliseconds: 900));
      expect(reveals, 0);
      await tester.tap(find.text('跳过动画'));
      expect(reveals, 1);
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.text('跳过动画'));
      expect(reveals, 1);
    },
  );
  testWidgets('normal timeline finishes at 1850ms without generating data', (
    tester,
  ) async {
    var reveals = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: GachaPresentation(
          record: record,
          settings: settings,
          onReveal: () {
            reveals++;
          },
        ),
      ),
    );
    await tester.pump(); // Establish the first ticker timestamp.
    await tester.pump(const Duration(milliseconds: 1800));
    expect(reveals, 0);
    await tester.pump(const Duration(milliseconds: 51));
    expect(reveals, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(reveals, 1);
  });
  testWidgets('system reduce motion overrides application preference', (
    tester,
  ) async {
    var reveals = 0;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: GachaPresentation(
          record: record,
          settings: settings,
          onReveal: () {
            reveals++;
          },
        ),
      ),
    );
    await tester.pump();
    expect(reveals, 1);
  });
  testWidgets('background stops presentation and resume reveals once', (
    tester,
  ) async {
    var reveals = 0;
    bool? feedback;
    await tester.pumpWidget(
      MaterialApp(
        home: GachaPresentation(
          record: record,
          settings: settings,
          onFeedbackPolicy: (enabled) => feedback = enabled,
          onReveal: () {
            reveals++;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 3));
    expect(reveals, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(reveals, 1);
    expect(feedback, isFalse);
    await tester.pump(const Duration(seconds: 3));
    expect(reveals, 1);
    expect(feedback, isFalse);
  });
  testWidgets(
    'demo works at 360px with 200 percent text and has no store dependency',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: const DemoPage(),
        ),
      );
      await tester.ensureVisible(find.text('体验抽一个'));
      await tester.tap(find.text('体验抽一个'));
      await tester.pumpAndSettle();
      expect(find.text('散步十分钟'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('vector art paints every stage in both themes', (tester) async {
    for (final dark in [false, true]) {
      for (final progress in [0.0, .2, .5, .8, 1.0]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: Scaffold(body: GachaMachine(progress: progress)),
          ),
        );
        expect(tester.takeException(), isNull);
      }
    }
  });
}
