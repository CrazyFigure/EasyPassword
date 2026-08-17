/// 搜索结果导航组件测试：目录展示，以及详情返回后的文件夹层级与定位。
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
    // 用足够多的普通条目把目标推到首屏之外，才能验证返回后不只是进入了
    // 文件夹，而且确实执行了滚动定位。
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

  testWidgets('搜索文件夹内条目，详情返回所属文件夹并定位到该行', (tester) async {
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

    await tester.tap(find.text('ZZZ 目标公司'));
    await pumpUntil(tester, () => find.text('密码详情').evaluate().isNotEmpty);

    // 文件夹页与详情页都保留在导航栈中，只点击当前详情 AppBar 内的返回键。
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
          find.text('工作账号').evaluate().isNotEmpty &&
          find.text('ZZZ 目标公司').hitTestable().evaluate().isNotEmpty,
    );

    // 目标位于名称排序末尾，偏移量大于零证明文件夹页消费了定位请求。
    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.controller!.offset, greaterThan(0));
  });
}
