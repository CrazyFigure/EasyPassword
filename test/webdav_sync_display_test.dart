/// WebDAV 同步结果展示与生命周期行为测试
library;

import 'package:easypassword/core/theme.dart';
import 'package:easypassword/services/database.dart';
import 'package:easypassword/state/app_state.dart';
import 'package:easypassword/ui/settings/webdav_setup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseService.overridePath = inMemoryDatabasePath;
  });

  late AppState state;

  setUp(() async {
    final db = await DatabaseService.db;
    await db.delete('settings');
    state = AppState();
    state.crypto.setKey(state.crypto.generateDeviceKey());
  });

  tearDown(() {
    state.dispose();
  });

  test('AppState 不监听生命周期切换事件（聚焦时不发起同步）', () {
    expect(state, isNot(isA<WidgetsBindingObserver>()));
  });

  test('AppState 初始化时恢复上次同步结果信息，且同步结束时持久化', () async {
    await DatabaseService.setSetting('sync_last_message', '自动同步完成，合并 3 个条目');
    final timeMillis = DateTime(2026, 8, 25, 12, 0, 0).millisecondsSinceEpoch;
    await DatabaseService.setSetting('sync_last_success', timeMillis.toString());

    await state.init();

    expect(state.syncMessage, '自动同步完成，合并 3 个条目');
    expect(state.lastSyncAt, isNotNull);
  });

  test('AppState.resetWebDavConfig 可清空已保存的 WebDAV 配置与状态', () async {
    await state.settings.setWebDavConfig(
      'https://dav.example.com/dav/',
      'user_abc',
      'pass_123',
      '/RemoteDir',
    );
    state.syncMessage = '同步中...';

    expect(await state.settings.getWebDavConfig(), isNotNull);

    await state.resetWebDavConfig();

    expect(await state.settings.getWebDavConfig(), isNull);
    expect(state.syncMessage, isNull);
    expect(await DatabaseService.getSetting('sync_last_message'), '');
  });

  testWidgets('WebDavSetupPage 在同步中展示转圈，并在同步完成后显示结果信息与Toast',
      (tester) async {
    state.webDavEnabled = true;
    state.syncMessage = '自动同步完成，合并 5 个条目';
    state.lastSyncAt = DateTime(2026, 8, 25, 15, 0, 0);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: const WebDavSetupPage(),
        ),
      ),
    );
    await tester.pump();

    // 验证页面展示了同步结果和最近同步时间
    expect(find.text('最近同步'), findsOneWidget);
    expect(find.textContaining('自动同步完成，合并 5 个条目'), findsOneWidget);
    expect(find.textContaining('2026-08-25 15:00:00'), findsOneWidget);

    // 模拟后台/定时同步开始
    state.syncing = true;
    state.notifyListeners();
    await tester.pump();

    // 验证自动同步卡片展示了正在同步中...
    expect(find.text('正在同步中...'), findsOneWidget);
    expect(find.text('正在同步...'), findsOneWidget);

    // 模拟后台/定时同步成功结束
    state.syncing = false;
    state.syncMessage = '自动同步完成';
    state.lastSyncAt = DateTime(2026, 8, 25, 15, 30, 0);
    state.notifyListeners();
    await tester.pump();

    // 验证 Toast 弹出
    expect(find.text('自动同步完成'), findsOneWidget);

    // 等待 Toast 动画与自动关闭定时器结束
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    // 验证页面状态信息更新
    expect(
        find.textContaining('2026-08-25 15:30:00 · 自动同步完成'), findsOneWidget);
  });

  testWidgets('WebDavSetupPage 点击重置可清空输入框并恢复默认远端路径', (tester) async {
    state.webDavEnabled = true;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: const WebDavSetupPage(),
        ),
      ),
    );
    await tester.pump();

    // 手动在输入框中填入自定义内容
    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'https://my-custom-dav.com/');
    await tester.enterText(textFields.at(1), 'my_user');
    await tester.enterText(textFields.at(2), '/CustomPath');
    await tester.pump();

    expect(find.text('https://my-custom-dav.com/'), findsOneWidget);
    expect(find.text('my_user'), findsOneWidget);
    expect(find.text('/CustomPath'), findsOneWidget);

    // 点击重置按钮弹出确认框
    await tester.tap(find.widgetWithText(OutlinedButton, '重置'));
    await tester.pumpAndSettle();

    expect(find.text('重置 WebDAV 配置'), findsOneWidget);

    // 确认重置
    await tester.tap(find.widgetWithText(FilledButton, '重置'));
    await tester.pump();
    // 推进时间以消解 Toast 与 sqflite 事务锁定时器
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();

    // 验证输入框恢复为默认初始状态
    expect(find.text('https://my-custom-dav.com/'), findsNothing);
    expect(find.text('my_user'), findsNothing);
    final pathField =
        tester.widget<TextField>(find.widgetWithText(TextField, '远端路径'));
    expect(pathField.controller?.text, '/EasyPassword');
  });
}
