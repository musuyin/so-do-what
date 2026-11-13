import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:so_do_what/app/ui.dart';
import 'package:so_do_what/core/domain/models.dart';
import 'package:so_do_what/features/settings/startup_recovery_page.dart';

void main() {
  testWidgets('启动失败不会显示空库，重试由明确操作触发', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: pickerTheme(Brightness.light),
        home: StartupRecoveryPage(
          databasePath: 'fictional.db',
          onRetry: () => retries++,
          onRecovered: () => fail('没有恢复操作'),
        ),
      ),
    );
    expect(find.text('暂时无法打开本地数据'), findsOneWidget);
    expect(find.text('创建第一个集合'), findsNothing);
    await tester.tap(find.text('重新打开'));
    await tester.pump();
    expect(retries, 1);
  });

  testWidgets('取消备份选择不执行修复，也不报告成功', (tester) async {
    var reads = 0;
    var recovered = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StartupRecoveryPage(
          databasePath: 'fictional.db',
          onRetry: () {},
          onRecovered: () => recovered++,
          backupReader: () async {
            reads++;
            return null;
          },
        ),
      ),
    );
    await tester.ensureVisible(find.text('选择备份恢复'));
    await tester.tap(find.text('选择备份恢复'));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(recovered, 0);
    expect(find.text('从备份修复本地数据？'), findsNothing);
    expect(find.text('选择备份恢复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360宽200%字号启动失败界面可滚动', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: pickerTheme(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: StartupRecoveryPage(
            databasePath: 'fictional.db',
            onRetry: () {},
            onRecovered: () {},
            error: const AppFailure('unsupportedVersion', '较新版本'),
          ),
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -1500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('需要更新版本'), findsOneWidget);
  });
}
