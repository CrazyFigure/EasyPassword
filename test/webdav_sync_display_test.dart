import 'package:easypassword/core/constants.dart';
import 'package:easypassword/core/theme.dart';
import 'package:easypassword/main.dart';
import 'package:easypassword/services/database.dart';
import 'package:easypassword/services/webdav_service.dart';
import 'package:easypassword/state/app_state.dart';
import 'package:easypassword/ui/common/app_toast.dart';
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
          navigatorKey: rootNavigatorKey,
          theme: AppTheme.build(),
          builder: (context, child) => GlobalSyncToastListener(
            child: child ?? const SizedBox.shrink(),
          ),
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

  test('SyncStats 格式化双向增删改明细与全量覆盖文案', () {
    // 1. 无数据变更
    const noChange = SyncStats(mode: WebDavSyncMode.automatic);
    expect(noChange.toSummaryMessage(), '同步完成：无数据变更');

    // 2. 本地拉取新增与修改，远端推送新增
    const diff1 = SyncStats(
      mode: WebDavSyncMode.automatic,
      localAdded: 2,
      localUpdated: 1,
      remoteAdded: 3,
    );
    expect(
      diff1.toSummaryMessage(),
      '同步完成：本地拉取新增 2 条、修改 1 条；远端推送新增 3 条',
    );

    // 3. 仅远端推送修改与删除
    const diff2 = SyncStats(
      mode: WebDavSyncMode.automatic,
      remoteUpdated: 1,
      remoteDeleted: 2,
    );
    expect(
      diff2.toSummaryMessage(),
      '同步完成：远端推送修改 1 条、删除 2 条',
    );

    // 4. 全量覆盖远端
    const overwriteRemote = SyncStats(
      mode: WebDavSyncMode.localToRemote,
      overwriteCount: 15,
    );
    expect(
      overwriteRemote.toSummaryMessage(),
      '全量覆盖远端完成：已推送全部 15 个条目',
    );

    // 5. 全量覆盖本地
    const overwriteLocal = SyncStats(
      mode: WebDavSyncMode.remoteToLocal,
      overwriteCount: 8,
    );
    expect(
      overwriteLocal.toSummaryMessage(),
      '全量覆盖本地完成：已覆盖 8 个条目',
    );
  });

  testWidgets('WebDavSetupPage 在窄屏（手机端）自适应为双行操作按钮且不折行',
      (tester) async {
    // 模拟常见手机屏幕宽度 360px
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

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

    // 验证三个按钮均正常渲染
    expect(find.widgetWithText(OutlinedButton, '重置'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '测试连接'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存配置'), findsOneWidget);

    // 验证按钮位置关系：重置与测试连接在同一水平行（垂直中心接近），保存配置在其下方
    final resetPos = tester.getCenter(find.widgetWithText(OutlinedButton, '重置'));
    final testPos =
        tester.getCenter(find.widgetWithText(OutlinedButton, '测试连接'));
    final savePos = tester.getCenter(find.widgetWithText(FilledButton, '保存配置'));

    expect((resetPos.dy - testPos.dy).abs(), lessThan(5));
    expect(savePos.dy, greaterThan(resetPos.dy + 20));
  });

  testWidgets('全局 Toast 监听器在任意界面下均能弹出同步完成提示', (tester) async {
    state.webDavEnabled = true;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          theme: AppTheme.build(),
          builder: (context, child) => GlobalSyncToastListener(
            child: child ?? const SizedBox.shrink(),
          ),
          home: const Scaffold(body: Text('主页')),
        ),
      ),
    );
    await tester.pump();

    // 模拟后台/定时同步开始并结束
    state.syncing = true;
    state.notifyListeners();
    await tester.pump();

    state.syncing = false;
    state.syncMessage = '同步完成：本地拉取新增 1 条；远端推送修改 2 条';
    state.notifyListeners();
    await tester.pump();

    // 验证全局 Toast 成功弹出
    expect(
      find.text('同步完成：本地拉取新增 1 条；远端推送修改 2 条'),
      findsOneWidget,
    );

    // 等待 Toast 动画与定时器消解
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
  });

  testWidgets('后台定时同步无数据变更时也能正常弹出 Toast 提示', (tester) async {
    state.webDavEnabled = true;

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          theme: AppTheme.build(),
          builder: (context, child) => GlobalSyncToastListener(
            child: child ?? const SizedBox.shrink(),
          ),
          home: const Scaffold(body: Text('主页')),
        ),
      ),
    );
    await tester.pump();

    // 模拟后台自动同步（background = true）且无数据变更
    state.syncing = true;
    state.lastSyncBackground = true;
    state.notifyListeners();
    await tester.pump();

    state.syncing = false;
    state.syncMessage = '同步完成：无数据变更';
    state.notifyListeners();
    await tester.pump();

    // 验证正常弹出 Toast 提示
    expect(find.text('同步完成：无数据变更'), findsOneWidget);

    // 等待 Toast 动画与定时器消解
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('同步完成：无数据变更'), findsNothing);
  });

  testWidgets('在未触发渲染/后台静默期间连续多次触发 Toast 时不会在 Overlay 中堆叠残留',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: const Scaffold(body: Text('主页')),
      ),
    );

    // 连续触发 10 次 Toast（模拟后台多轮同步但未驱动帧渲染的极端场景）
    for (int i = 0; i < 10; i++) {
      showAppToast(null, '提示信息 #$i');
    }

    // 模拟前台首次恢复渲染帧
    await tester.pump();

    // 仅最后一条 Toast 会被挂载渲染，前面的所有 OverlayEntry 均已被彻底移除，杜绝阴影多层叠加
    for (int i = 0; i < 9; i++) {
      expect(find.text('提示信息 #$i'), findsNothing);
    }
    expect(find.text('提示信息 #9'), findsOneWidget);

    // 等待最后一条 Toast 倒计时结束并淡出消解
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('提示信息 #9'), findsNothing);
  });
}
