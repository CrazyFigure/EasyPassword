/// 新增元素后自动定位测试：新条目必须被滚进视野，用户不该自己去翻。
///
/// 两个层级各测一处：文件夹内页（列表行，按索引算位置）与密码详情页
/// （账号卡片，追加在末尾）。根列表与文件夹内页共用 revealIndex，
/// 因此不再重复覆盖。
library;

import 'package:easypassword/core/constants.dart';
import 'package:easypassword/models/folder.dart';
import 'package:easypassword/models/password_item.dart';
import 'package:easypassword/services/database.dart';
import 'package:easypassword/state/app_state.dart';
import 'package:easypassword/ui/detail/password_detail_page.dart';
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

  setUp(() async {
    final db = await DatabaseService.db;
    await db.delete('api_keys');
    await db.delete('accounts');
    await db.delete('password_items');
    await db.delete('folders');

    state = AppState();
    state.crypto.setKey(state.crypto.generateDeviceKey());
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
  });

  /// 让出真实事件循环若干轮，等 sqflite 的真实 IO 与随后的重建完成。
  ///
  /// pumpAndSettle 走 fake async 时钟，等不到真实数据库读写；反过来只
  /// runAsync 而 pump 不带时长，滚动动画的时钟又不会前进，animateTo 永远
  /// 结束不了。因此两者都要：先让出真实时间等 IO，再推进假时钟跑动画。
  Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    // 收尾：把仍在跑的滚动动画推到结束，否则断言会读到中间值
    await tester.pumpAndSettle();
  }

  /// 当前页面里唯一竖向可滚动列表的滚动位置
  ScrollPosition scrollPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable).first).position;

  group('文件夹内页', () {
    late Folder folder;

    /// 造足够多的条目让列表可滚动；名称用序号保证名称序 == 写入序，
    /// 这样"第 N 条"在两种排序模式下都指向同一行，断言不依赖排序规则。
    ///
    /// 必须由调用方包在 [WidgetTester.runAsync] 里：testWidgets 的函数体跑在
    /// fake async 区域，sqflite 的真实 IO 在假时钟下永远不会完成。
    Future<void> seed(int count) async {
      folder = await state.data.addFolder(ItemType.password, '工作');
      for (var i = 0; i < count; i++) {
        await state.data.addItem(
          ItemType.password,
          // 补零保证 10 之后仍按数字序排列
          '条目${i.toString().padLeft(2, '0')}',
          folderId: folder.id,
        );
      }
      state.passwordSortMode = 'name_asc';
    }

    Future<void> pumpFolder(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            home: FolderPage(type: ItemType.password, folder: folder),
          ),
        ),
      );
      for (var i = 0; i < 60; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byType(ListTile).evaluate().isNotEmpty) return;
      }
      fail('文件夹页在超时前没有加载出条目');
    }

    testWidgets('新增条目后新行可见且不再停在顶部', (tester) async {
      await tester.runAsync(() => seed(30));
      await pumpFolder(tester);
      expect(scrollPosition(tester).pixels, 0);

      // 点 FAB 走真实新增路径：填名称 → 保存
      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, '条目99');
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await settle(tester);

      // 列表已滚离顶部，说明定位生效
      expect(scrollPosition(tester).pixels, greaterThan(0));
      // 且新条目真的渲染在视野里（不只是数据存下来了）
      expect(find.text('条目99'), findsOneWidget);
    });

    testWidgets('列表短到无需滚动时不产生滚动', (tester) async {
      await tester.runAsync(() => seed(2));
      await pumpFolder(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, '条目99');
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await settle(tester);

      // 一屏放得下时不该有多余的滚动动作
      final position = scrollPosition(tester);
      expect(position.maxScrollExtent, 0);
      expect(position.pixels, 0);
      expect(find.text('条目99'), findsOneWidget);
    });
  });

  group('密码详情页', () {
    late PasswordItem item;

    /// 造足够多的账号，让页面长过一屏。
    /// 同样必须由调用方包在 [WidgetTester.runAsync] 里。
    Future<void> seed(int count) async {
      item = await state.data.addItem(ItemType.password, 'oyunfor');
      for (var i = 0; i < count; i++) {
        await state.data.addAccount(item.id, 'user$i', 'pwd$i');
      }
    }

    Future<void> pumpDetail(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(home: PasswordDetailPage(item: item)),
        ),
      );
      // 等到账号卡片真正渲染出来为止。
      // 不能等「添加账号」文案：加载完成后按钮与新增表单标题都叫这个名字，
      // 而账号行头「账号 1」只在列表建好后才有。
      for (var i = 0; i < 80; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 20));
        if (find.text('账号 1').evaluate().isNotEmpty) return;
      }
      fail('详情页在超时前没有加载出账号列表');
    }

    /// 点一个可能位于首屏之外的控件。
    ///
    /// 详情页是 ListView，屏幕外的子项根本没被 build，光靠 warnIfMissed
    /// 也点不到，必须先把它滚进来。页面内还嵌着账号列表的 ReorderableListView，
    /// 因此要显式指定外层这个 Scrollable，否则 finder 会命中多个。
    Future<void> tapOffscreen(WidgetTester tester, Finder target) async {
      await tester.scrollUntilVisible(
        target,
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      await tester.tap(target);
      await settle(tester);
    }

    testWidgets('点「添加账号」后表单被滚进视野', (tester) async {
      await tester.runAsync(() => seed(8));
      await pumpDetail(tester);

      expect(scrollPosition(tester).pixels, 0);
      expect(scrollPosition(tester).maxScrollExtent, greaterThan(0),
          reason: '夹具账号数需多到让页面可滚动，否则这条测试无意义');

      await tapOffscreen(
          tester, find.widgetWithText(OutlinedButton, '添加账号'));

      // 表单已就位，且它是可见的（回归「点完按钮看不到输入框」）
      final saveBtn = find.widgetWithText(FilledButton, '保存');
      expect(saveBtn, findsOneWidget);
      final formBottom = tester.getRect(saveBtn).bottom;
      expect(formBottom, lessThanOrEqualTo(800),
          reason: '展开的表单必须落在视口内，不能被顶出屏幕');
    });

    testWidgets('保存新账号后滚动到新卡片', (tester) async {
      await tester.runAsync(() => seed(8));
      await pumpDetail(tester);

      await tapOffscreen(
          tester, find.widgetWithText(OutlinedButton, '添加账号'));
      await tester.enterText(find.byType(TextField).first, 'newcomer');
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await settle(tester);

      // 新账号追加在末尾，页面应停在底部附近
      final position = scrollPosition(tester);
      expect(position.pixels, closeTo(position.maxScrollExtent, 1));
      final accounts =
          await tester.runAsync(() => state.data.listAccounts(item.id));
      expect(accounts!.last.username, 'newcomer');
    });
  });
}
