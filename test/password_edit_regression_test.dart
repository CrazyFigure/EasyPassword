/// 密码详情页编辑回归测试：覆盖旧明文缓存导致保存后回退的完整链路。
library;

import 'package:easypassword/core/theme.dart';
import 'package:easypassword/models/password_item.dart';
import 'package:easypassword/services/database.dart';
import 'package:easypassword/state/app_state.dart';
import 'package:easypassword/ui/detail/password_detail_page.dart';
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
  late PasswordItem item;

  setUp(() async {
    state = AppState();
    state.crypto.setKey(state.crypto.generateDeviceKey());
    final db = await DatabaseService.db;
    await db.delete('api_keys');
    await db.delete('accounts');
    await db.delete('password_items');
    await db.delete('folders');
    item = await state.data.addItem('password', '回归测试站点');
    await state.data.addAccount(item.id, 'tester', 'old-password');
  });

  tearDown(() async {
    state.dispose();
    await DatabaseService.resetForTest();
  });

  testWidgets('修改密码后再次只改备注不会把旧密码写回', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.build(),
          home: PasswordDetailPage(item: item),
        ),
      ),
    );
    await _waitForUi(tester, find.text('账号 1'));

    await _openAccountEditor(tester);
    await tester.enterText(_fieldByLabel('密码'), 'new-password');
    await tester.tap(find.text('保存'));
    await _waitForUi(tester, find.text('编辑账号'), present: false);

    var savedAccount =
        (await tester.runAsync(() => state.data.listAccounts(item.id)))!.single;
    expect(
      await tester.runAsync(() => state.data.plainPassword(savedAccount)),
      'new-password',
    );

    // 再次打开时必须回填刚保存的新密码，而不是卡片中残留的旧明文缓存。
    await _openAccountEditor(tester);
    final passwordInput = tester.widget<EditableText>(
      find.descendant(
        of: _fieldByLabel('密码'),
        matching: find.byType(EditableText),
      ),
    );
    expect(passwordInput.controller.text, 'new-password');

    // 只改备注再保存，数据库中的密码也必须保持新值。
    await tester.enterText(_fieldByLabel('用户级备注'), '只修改备注');
    await tester.tap(find.text('保存'));
    await _waitForUi(tester, find.text('编辑账号'), present: false);
    savedAccount =
        (await tester.runAsync(() => state.data.listAccounts(item.id)))!.single;
    expect(savedAccount.note, '只修改备注');
    expect(
      await tester.runAsync(() => state.data.plainPassword(savedAccount)),
      'new-password',
    );
  });
}

/// 从账号卡片的更多菜单进入编辑态，并等待密码解密及表单动画结束。
Future<void> _openAccountEditor(WidgetTester tester) async {
  await tester.tap(find.byTooltip('更多操作'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('编辑'));
  await _waitForUi(tester, find.text('编辑账号'));
}

/// 交替推进真实事件循环与 Flutter 假时钟，直到目标控件出现或消失。
///
/// 详情页的数据查询走 sqflite 真实 IO，而菜单和输入框使用测试假时钟；两者都
/// 必须推进。编辑框获得焦点后光标会持续闪烁，因此不能使用 `pumpAndSettle`。
Future<void> _waitForUi(
  WidgetTester tester,
  Finder target, {
  bool present = true,
}) async {
  for (var i = 0; i < 50; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (target.evaluate().isNotEmpty == present) return;
  }
  fail(
    '等待界面状态超时：${target.describeMatch(Plurality.one)}，'
    '期望${present ? '出现' : '消失'}',
  );
}

/// 按输入框标签精确定位对应 TextField，避免同页其他文本干扰测试操作。
Finder _fieldByLabel(String label) {
  return find.ancestor(
    of: find.text(label),
    matching: find.byType(TextField),
  );
}
