import 'package:easypassword/core/theme.dart';
import 'package:easypassword/ui/common/detail_field_row.dart';
import 'package:easypassword/ui/common/row_action_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 在给定宽度下渲染若干字段行
Future<void> _pumpRows(
  WidgetTester tester,
  List<DetailFieldRow> rows, {
  double width = 900,
}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: Column(children: rows),
      ),
    ),
  );
  await tester.pump();
}

/// 取某个文本的左边缘 x 坐标
double _left(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dx;

void main() {
  testWidgets('各字段的值从同一竖向位置开始，标签长短不影响对齐', (tester) async {
    // 「用户名」三字与「平台密码」四字标签长度不同，值仍需左对齐
    await _pumpRows(tester, const [
      DetailFieldRow(label: '用户名', value: 'alice@example.com'),
      DetailFieldRow(label: '平台密码', value: '******'),
      DetailFieldRow(label: '备注', value: '工作账号'),
    ]);

    final valueLefts = [
      _left(tester, 'alice@example.com'),
      _left(tester, '******'),
      _left(tester, '工作账号'),
    ];
    for (final x in valueLefts) {
      expect(x, closeTo(valueLefts.first, 0.5));
    }

    // 标签本身也应左对齐于同一条线
    final labelLefts = [
      _left(tester, '用户名'),
      _left(tester, '平台密码'),
      _left(tester, '备注'),
    ];
    for (final x in labelLefts) {
      expect(x, closeTo(labelLefts.first, 0.5));
    }
  });

  testWidgets('备注与其他字段同格式，不额外带冒号', (tester) async {
    await _pumpRows(tester, const [
      DetailFieldRow(label: '备注', value: '工作账号'),
    ]);

    // 回归「备注：xxx」与上方字段格式不一致的问题
    expect(find.text('工作账号'), findsOneWidget);
    expect(find.textContaining('备注：'), findsNothing);
  });

  testWidgets('用户名与密码只有一个有值时，另一行占位且不错位', (tester) async {
    // 网站可能只存密码不存用户名，空行需保留以维持对齐
    await _pumpRows(tester, const [
      DetailFieldRow(label: '用户名', value: ''),
      DetailFieldRow(label: '密码', value: '****'),
    ]);

    expect(find.text('未设置'), findsOneWidget);
    expect(_left(tester, '未设置'), closeTo(_left(tester, '****'), 0.5));
  });

  testWidgets('解密未完成时不显示未设置占位', (tester) async {
    await _pumpRows(tester, const [
      DetailFieldRow(label: '密码', value: '', pending: true),
    ]);

    // pending 期间值为空只是尚未就绪，不能误判为「没有密码」
    expect(find.text('未设置'), findsNothing);
  });

  testWidgets('显示/隐藏按钮排在复制之前', (tester) async {
    await _pumpRows(tester, [
      DetailFieldRow(
        label: '密码',
        value: '****',
        obscurable: true,
        onToggle: () {},
        onCopy: () async => 'secret',
      ),
    ]);

    final eyeX = tester.getCenter(find.byTooltip('显示')).dx;
    final copyX = tester.getCenter(find.byTooltip('复制密码')).dx;
    expect(eyeX, lessThan(copyX));
  });

  testWidgets('空值行不渲染复制与显示按钮', (tester) async {
    await _pumpRows(tester, [
      DetailFieldRow(
        label: '用户名',
        value: '',
        obscurable: true,
        onToggle: () {},
        onCopy: () async => '',
      ),
    ]);

    // 没有值时按钮无意义，避免复制空串
    expect(find.byTooltip('复制用户名'), findsNothing);
    expect(find.byTooltip('显示'), findsNothing);
  });

  testWidgets('窄屏下字段行不溢出', (tester) async {
    await _pumpRows(
      tester,
      [
        DetailFieldRow(
          label: '平台密码',
          value: 'a-fairly-long-secret-value-1234567890',
          obscurable: true,
          onToggle: () {},
          onCopy: () async => 'x',
          menu: RowActionMenu(
            size: 16,
            actions: [
              RowAction(label: '编辑', icon: Icons.edit, onSelected: () {}),
            ],
          ),
        ),
      ],
      width: 360,
    );

    expect(tester.takeException(), isNull);
  });
}
