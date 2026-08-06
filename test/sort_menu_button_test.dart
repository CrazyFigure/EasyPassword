/// 排序按钮组件测试：两种规则无需展开菜单即可通过形态辨认。
library;

import 'package:easypassword/core/constants.dart';
import 'package:easypassword/state/app_state.dart';
import 'package:easypassword/ui/item_list_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('密码与 API Key 使用各自排序状态和不同按钮形态', (tester) async {
    final state = AppState()
      ..passwordSortMode = 'custom'
      ..apikeySortMode = 'name_asc';

    /// 按指定分区重建列表页，用于核对同一状态对象中的两套排序外观。
    Future<void> pumpList(String type) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            home: Scaffold(body: ItemListView(type: type)),
          ),
        ),
      );
    }

    await pumpList(ItemType.password);
    final customFinder = find.widgetWithIcon(
      IconButton,
      Icons.drag_indicator_rounded,
    );
    expect(customFinder, findsOneWidget);
    expect(find.byTooltip('当前：自定义排序'), findsOneWidget);
    final customButton = tester.widget<IconButton>(customFinder);
    expect(
      customButton.style?.shape?.resolve(<WidgetState>{}),
      isA<RoundedRectangleBorder>(),
    );

    await pumpList(ItemType.apikey);
    final nameFinder = find.widgetWithIcon(
      IconButton,
      Icons.sort_by_alpha_rounded,
    );
    expect(nameFinder, findsOneWidget);
    expect(find.byTooltip('当前：按名称升序'), findsOneWidget);
    final nameButton = tester.widget<IconButton>(nameFinder);
    expect(
      nameButton.style?.shape?.resolve(<WidgetState>{}),
      isA<CircleBorder>(),
    );

    // 先卸载 Provider 再释放状态，避免测试框架清理监听器时访问已释放对象。
    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
