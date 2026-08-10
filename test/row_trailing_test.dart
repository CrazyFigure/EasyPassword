/// 列表行尾紧凑度测试：「⋮」与「›」不该过度挤占标题空间。
///
/// 回归的是移动端观感问题——行尾两个图标各自带着默认的 48px 触摸区与
/// ListTile 的 16px 右内边距，横向合计吃掉近百像素，条目名称被过早截断。
library;

import 'package:easypassword/core/theme.dart';
import 'package:easypassword/ui/common/row_trailing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 按真实列表行的结构渲染一行，返回该行的 ListTile finder
  Future<void> pumpRow(
    WidgetTester tester, {
    required String title,
    double width = 393,
  }) async {
    tester.view.physicalSize = Size(width, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: Scaffold(
          body: ListView(
            children: [
              Card(
                child: ListTile(
                  contentPadding: kRowContentPadding,
                  leading: const SizedBox(width: 40, height: 40),
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('副标题'),
                  trailing: RowTrailing(
                    menuTooltip: '条目操作',
                    onMenu: (_) async {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('行尾图标组的总宽度受控', (tester) async {
    await pumpRow(tester, title: '示例条目');

    // 「⋮」热区 40 + 箭头 20 + Tooltip 包装的少量余量。
    // 旧实现是 IconButton 默认 48 + Icon 24 = 72，外加 ListTile 的 16px
    // 右缩进（本组件配套的 kRowContentPadding 已收到 4），合计约 88。
    // 这里卡在 70：既锁住收益，也不逼着后续为凑数字牺牲触摸区。
    final trailingWidth = tester.getSize(find.byType(RowTrailing)).width;
    expect(trailingWidth, lessThanOrEqualTo(70));
  });

  testWidgets('「⋮」的触摸区不小于无障碍下限', (tester) async {
    await pumpRow(tester, title: '示例条目');

    // 收紧的是视觉留白，不是可点区域：热区必须仍然好点
    final hit = tester.getSize(find.byTooltip('条目操作'));
    expect(hit.width, greaterThanOrEqualTo(40));
    expect(hit.height, greaterThanOrEqualTo(40));
  });

  testWidgets('箭头贴近右缘，不在中间留大片空白', (tester) async {
    await pumpRow(tester, title: '示例条目');

    // 箭头右边缘到卡片右边缘的距离应当很小（卡片本身还有 margin）
    final arrowRight =
        tester.getRect(find.byIcon(Icons.chevron_right)).right;
    final cardRight = tester.getRect(find.byType(Card)).right;
    expect(cardRight - arrowRight, lessThanOrEqualTo(10));
  });

  testWidgets('长标题能用上让出来的横向空间', (tester) async {
    const longTitle = '一个相当长的网站条目名称用来测试截断';
    await pumpRow(tester, title: longTitle);

    // 标题区宽度 = 屏宽 - 左缩进 - 头像 - 行尾组 - 卡片 margin，
    // 收紧行尾后应当明显多于半屏，否则说明留白又被吃回去了
    final titleWidth = tester.getSize(find.text(longTitle)).width;
    expect(titleWidth, greaterThan(393 / 2));
  });
}
