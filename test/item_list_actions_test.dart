/// 主列表单条操作测试：条目自带「⋮」菜单可移动到文件夹，
/// 删除文件夹时内部条目一并删除。
library;

import 'package:easypassword/core/constants.dart';
import 'package:easypassword/services/database.dart';
import 'package:easypassword/state/app_state.dart';
import 'package:easypassword/ui/item_list_view.dart';
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
    await db.delete('api_keys');
    await db.delete('accounts');
    await db.delete('password_items');
    await db.delete('folders');

    // 与 folder_page_sort_test 一致：直接用 AppState 自带的 DataService 备数据
    state = AppState();
    state.crypto.setKey(state.crypto.generateDeviceKey());
    state.passwordSortMode = 'name_asc';
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
  });

  /// 挂载主列表并等到根条目渲染出来。
  ///
  /// 库操作必须放进 runAsync：testWidgets 默认的 fake async 时钟不会推进
  /// sqflite 的真实 IO，直接 await 会永久挂起。
  Future<void> pumpList(WidgetTester tester) async {
    await tester.runAsync(() => state.refresh());
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(
          home: Scaffold(body: ItemListView(type: ItemType.password)),
        ),
      ),
    );
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (find.byType(ListTile).evaluate().isNotEmpty) return;
    }
    fail('主列表在超时前没有加载出条目');
  }

  /// 点击后等界面稳定：菜单/弹窗的回调里有库写入，同样要走真实事件循环
  Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
  }

  testWidgets('根条目行提供「⋮」操作按钮，非批量模式即可用', (tester) async {
    await tester
        .runAsync(() => state.data.addItem(ItemType.password, '公司邮箱'));
    await pumpList(tester);

    expect(find.byTooltip('条目操作'), findsOneWidget);
  });

  testWidgets('通过条目「⋮」菜单可把单条移动到文件夹', (tester) async {
    final folder = await tester
        .runAsync(() => state.data.addFolder(ItemType.password, '工作'));
    await tester
        .runAsync(() => state.data.addItem(ItemType.password, '公司邮箱'));
    await pumpList(tester);

    await tapAndSettle(tester, find.byTooltip('条目操作'));
    await tapAndSettle(tester, find.text('移动到文件夹'));
    // 弹窗里选中目标文件夹（菜单项已关闭，此时「工作」是弹窗中的目标行）
    await tapAndSettle(tester, find.text('工作').last);

    final inFolder = await tester.runAsync(
        () => state.data.listItems(ItemType.password, folderId: folder!.id));
    expect(inFolder!.map((e) => e.name), ['公司邮箱']);
    // 已不在根目录
    final root =
        await tester.runAsync(() => state.data.listItems(ItemType.password));
    expect(root, isEmpty);
  });

  testWidgets('删除文件夹时内部条目一并删除', (tester) async {
    final folder = await tester
        .runAsync(() => state.data.addFolder(ItemType.password, '工作'));
    await tester.runAsync(() =>
        state.data.addItem(ItemType.password, '公司邮箱', folderId: folder!.id));
    // 根目录留一条，用于验证只删文件夹内的条目
    await tester
        .runAsync(() => state.data.addItem(ItemType.password, '个人邮箱'));
    await pumpList(tester);

    await tapAndSettle(tester, find.byTooltip('文件夹操作'));
    await tapAndSettle(tester, find.text('删除文件夹'));
    // 确认框应说明条目会一起删除
    expect(find.textContaining('一并删除'), findsOneWidget);
    await tapAndSettle(tester, find.widgetWithText(FilledButton, '删除'));

    final folders =
        await tester.runAsync(() => state.data.listFolders(ItemType.password));
    expect(folders, isEmpty);
    // 文件夹内条目被删除，而不是移回根目录
    final remaining = await tester.runAsync(
        () => state.data.listItems(ItemType.password, allFolders: true));
    expect(remaining!.map((e) => e.name), ['个人邮箱']);
  });
}
