/// 搜索结果导航组件测试：目录展示，以及详情返回后回到原搜索结果与滚动位置。
library;

import 'package:easypassword/core/constants.dart';
import 'package:easypassword/services/database.dart';
import 'package:easypassword/state/app_state.dart';
import 'package:easypassword/ui/home_page.dart';
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
    state.currentTab = 'search';
    state.passwordSortMode = 'name_asc';

    final folder = await state.data.addFolder(ItemType.password, '工作账号');
    // 用足够多的同名前缀条目撑出长结果列表，才能验证返回后滚动位置被保留。
    for (var i = 0; i < 24; i++) {
      await state.data.addItem(
        ItemType.password,
        '条目 ${i.toString().padLeft(2, '0')}',
        folderId: folder.id,
      );
    }
    await state.data.addItem(
      ItemType.password,
      'ZZZ 目标公司',
      folderId: folder.id,
    );
  });

  tearDown(() async {
    state.dispose();
    await DatabaseService.resetForTest();
  });

  /// 让出 sqflite 使用的真实事件循环，直到指定界面条件成立。
  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition,
  ) async {
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      if (condition()) return;
    }
    fail('界面在超时前没有进入预期状态');
  }

  testWidgets('搜索文件夹内条目展示所在目录', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: HomePage()),
      ),
    );

    await tester.enterText(find.byType(TextField), '目标公司');
    await pumpUntil(tester, () => find.text('目录：工作账号').evaluate().isNotEmpty);

    // 目录作为独立的第二行信息展示，不能挤占命中摘要。
    final resultTile = tester.widget<ListTile>(find.byType(ListTile));
    expect(resultTile.isThreeLine, isTrue);
  });

  testWidgets('详情返回后回到原搜索结果并保留滚动位置', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: state,
        child: const MaterialApp(home: HomePage()),
      ),
    );

    await tester.enterText(find.byType(TextField), '条目');
    await pumpUntil(
        tester, () => find.byType(ListTile).evaluate().isNotEmpty);

    // 结果列表的滚动状态（排除搜索框内部的 Scrollable）
    ScrollPosition resultPosition() => tester
        .state<ScrollableState>(find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first)
        .position;

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    final offsetBefore = resultPosition().pixels;
    expect(offsetBefore, greaterThan(0));

    await tester.tap(find.byType(ListTile).hitTestable().first);
    await pumpUntil(tester, () => find.text('密码详情').evaluate().isNotEmpty);

    // 打开详情不切换 Tab，搜索页仍在下层路由中
    expect(state.currentTab, 'search');

    final detailAppBar = find.widgetWithText(AppBar, '密码详情');
    await tester.tap(
      find.descendant(
        of: detailAppBar,
        matching: find.byIcon(Icons.arrow_back),
      ),
    );
    await pumpUntil(
      tester,
      () =>
          find.text('密码详情').evaluate().isEmpty &&
          find.byType(ListTile).hitTestable().evaluate().isNotEmpty,
    );

    // 关键词与结果列表原样保留，且静默刷新后滚动位置不变
    expect(find.text('全局搜索'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '条目');
    expect(resultPosition().pixels, offsetBefore);
  });
}
