/// 文件夹内页排序测试：排序入口与根列表一致，列表顺序跟随分区设置。
library;

import 'package:easypassword/core/constants.dart';
import 'package:easypassword/models/folder.dart';
import 'package:easypassword/services/database.dart';
import 'package:easypassword/state/app_state.dart';
import 'package:easypassword/ui/folder_page.dart';
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
  late Folder folder;

  setUp(() async {
    final db = await DatabaseService.db;
    await db.delete('api_keys');
    await db.delete('accounts');
    await db.delete('password_items');
    await db.delete('folders');

    // AppState 在构造函数里就建好了服务实例（data 是 late final，不可替换），
    // 因此直接用它自带的 DataService 准备夹具数据。
    state = AppState();
    state.crypto.setKey(state.crypto.generateDeviceKey());
    final data = state.data;
    folder = await data.addFolder(ItemType.password, '工作');
    // 按乱序写入，让 sort_order 与名称序不一致，才能验证展示时确实重排过
    for (final name in ['Zoom', '百度', 'Apple', '阿里云']) {
      await data.addItem(ItemType.password, name, folderId: folder.id);
    }
    state.passwordSortMode = 'name_asc';
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
  });

  /// 挂载文件夹页并等待首次加载完成。
  ///
  /// 不能用 pumpAndSettle：加载中的 CircularProgressIndicator 是无限动画，
  /// 在它消失之前 settle 永远不会返回。这里反复让出真实事件循环，直到数据
  /// 落地、列表渲染出来为止——固定等一次在并发跑测试时会偶发落空。
  Future<void> pumpFolder(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: MaterialApp(
          home: FolderPage(type: ItemType.password, folder: folder),
        ),
      ),
    );
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
      if (find.byType(ListTile).evaluate().isNotEmpty) return;
    }
    fail('文件夹页在超时前没有加载出条目');
  }

  testWidgets('文件夹页展示当前排序规则入口', (tester) async {
    await pumpFolder(tester);
    // 与根列表同一个按钮：名称模式下是字母排序图标 + 说明规则的 tooltip
    expect(
      find.widgetWithIcon(IconButton, Icons.sort_by_alpha_rounded),
      findsOneWidget,
    );
    expect(find.byTooltip('当前：按名称排序（数字在前，汉字按拼音）'), findsOneWidget);
  });

  testWidgets('文件夹内条目按拼音规则展示，与外部规则一致', (tester) async {
    await pumpFolder(tester);
    // 取 ListTile 标题的实际渲染顺序：aliyun < apple < baidu < zoom
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles, ['阿里云', 'Apple', '百度', 'Zoom']);
  });

  testWidgets('切换到自定义排序后按 sort_order 展示', (tester) async {
    state.passwordSortMode = 'custom';
    await pumpFolder(tester);
    // 自定义模式回到写入顺序，证明本页确实跟随分区设置而非固定名称序
    final titles = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .map((tile) => (tile.title as Text).data)
        .toList();
    expect(titles, ['Zoom', '百度', 'Apple', '阿里云']);
  });

  /// 点击后等界面稳定：菜单与弹窗回调里有库写入，需让出真实事件循环
  /// （pumpAndSettle 走的是 fake async 时钟，等不到 sqflite 的真实 IO）
  Future<void> tapAndSettle(WidgetTester tester, Finder target) async {
    await tester.tap(target);
    for (var i = 0; i < 50; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
  }

  testWidgets('文件夹内每条条目都有「⋮」操作按钮', (tester) async {
    await pumpFolder(tester);
    // 4 条夹具数据，非批量模式下每行一个入口
    expect(find.byTooltip('条目操作'), findsNWidgets(4));
  });

  testWidgets('通过条目「⋮」菜单可把单条移出到上一级', (tester) async {
    await pumpFolder(tester);

    await tapAndSettle(tester, find.byTooltip('条目操作').first);
    await tapAndSettle(tester, find.text('移动到文件夹'));
    // 文件夹内页允许移出，弹窗里应有该选项
    expect(find.text('移出到上一级'), findsOneWidget);
    await tapAndSettle(tester, find.text('移出到上一级'));

    // 列表首条是「阿里云」（名称序），移出后它应落到根目录
    final root = await tester
        .runAsync(() => state.data.listItems(ItemType.password));
    expect(root!.map((e) => e.name), ['阿里云']);
    // listItems 按 sort_order 返回（与展示用的名称序不同），故不比较顺序
    final inFolder = await tester.runAsync(
        () => state.data.listItems(ItemType.password, folderId: folder.id));
    expect(inFolder!.map((e) => e.name),
        unorderedEquals(['Apple', '百度', 'Zoom']));
  });

  testWidgets('通过条目「⋮」菜单可删除单条', (tester) async {
    await pumpFolder(tester);

    await tapAndSettle(tester, find.byTooltip('条目操作').first);
    await tapAndSettle(tester, find.text('删除条目'));
    await tapAndSettle(tester, find.widgetWithText(FilledButton, '删除'));

    // 首条「阿里云」被删除，其余三条保留且未被移出文件夹
    final inFolder = await tester.runAsync(
        () => state.data.listItems(ItemType.password, folderId: folder.id));
    expect(inFolder!.map((e) => e.name),
        unorderedEquals(['Apple', '百度', 'Zoom']));
    final root = await tester
        .runAsync(() => state.data.listItems(ItemType.password));
    expect(root, isEmpty);
  });
}
