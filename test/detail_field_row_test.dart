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

  testWidgets('有值行与空值行等高，行距不因缺值变形', (tester) async {
    // 回归截图问题：空值行没有按钮时高度塌陷，卡片内行距忽大忽小
    await _pumpRows(tester, [
      const DetailFieldRow(label: '用户名', value: ''),
      DetailFieldRow(
        label: '平台密码',
        value: '****',
        obscurable: true,
        onToggle: () {},
        onCopy: () async => 'x',
      ),
      DetailFieldRow(
        label: '备注',
        value: '1213',
        onCopy: () async => '1213',
      ),
    ]);

    final heights = tester
        .widgetList<DetailFieldRow>(find.byType(DetailFieldRow))
        .map((row) => tester.getSize(find.byWidget(row)).height)
        .toList();
    expect(heights, hasLength(3));
    for (final h in heights) {
      expect(h, closeTo(heights.first, 0.5));
    }
  });

  testWidgets('全部字段皆为空时各行仍等高', (tester) async {
    await _pumpRows(tester, const [
      DetailFieldRow(label: '用户名', value: ''),
      DetailFieldRow(label: '密码', value: ''),
    ]);

    final heights = tester
        .widgetList<DetailFieldRow>(find.byType(DetailFieldRow))
        .map((row) => tester.getSize(find.byWidget(row)).height)
        .toList();
    expect(heights.last, closeTo(heights.first, 0.5));
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
        ),
      ],
      width: 360,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('字段行不为卡片级菜单预留第三个操作列', (tester) async {
    // 回归移动端用户名被截断的问题：字段行右侧此前固定排三个插槽，
    // 而第三列（卡片级「更多」菜单）在所有调用点都是空的，白占一个插槽宽度。
    await _pumpRows(
      tester,
      [
        DetailFieldRow(
          label: '用户名',
          value: '17877783200',
          onCopy: () async => 'x',
        ),
      ],
      width: 360,
    );

    // 有值行只应出现「复制」一个插槽；空插槽仅用于对齐，不应多出第三个
    expect(find.byType(ActionSlot), findsNWidgets(2));
  });

  testWidgets('窄屏下 11 位手机号能完整显示', (tester) async {
    // 截图里用户名被截成「215731833…」。以 393 逻辑宽（常见手机）为准，
    // 扣掉页面与卡片留白后模拟字段行的实际可用宽度。
    const phone = '17877783200';
    const pagePadding = 16.0 * 2;
    const cardPadding = 14.0 * 2;
    await _pumpRows(
      tester,
      [
        DetailFieldRow(
          label: '用户名',
          value: phone,
          onCopy: () async => phone,
        ),
      ],
      width: 393 - pagePadding - cardPadding,
    );

    // 文本没被省略号截断：渲染宽度足以容纳完整内容
    final textWidget = tester.widget<Text>(find.text(phone));
    final painter = TextPainter(
      text: TextSpan(text: phone, style: textWidget.style),
      textDirection: TextDirection.ltr,
    )..layout();
    expect(tester.getSize(find.text(phone)).width,
        greaterThanOrEqualTo(painter.width));
  });
}
