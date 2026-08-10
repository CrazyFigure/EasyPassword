import 'package:easypassword/core/theme.dart';
import 'package:easypassword/ui/common/inline_edit_form.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 账号类表单的三个字段：用户名 / 密码 / 备注
const _accountFields = [
  InlineField(key: 'username', label: '用户名'),
  InlineField(key: 'password', label: '密码', obscure: true),
  InlineField(key: 'note', label: '用户级备注'),
];

/// 渲染一个 InlineEditForm，返回一个取保存结果的闭包
Future<Map<String, String>? Function()> _pumpForm(
  WidgetTester tester, {
  List<InlineField> fields = _accountFields,
  Set<String> requiredKeys = const {},
  Set<String> requireAnyOf = const {'username', 'password'},
}) async {
  Map<String, String>? saved;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: Scaffold(
        body: InlineEditForm(
          title: '添加账号',
          requiredKeys: requiredKeys,
          requireAnyOf: requireAnyOf,
          fields: fields,
          onCancel: () {},
          onSave: (v) => saved = v,
        ),
      ),
    ),
  );
  await tester.pump();
  return () => saved;
}

/// 按标签填写输入框
Future<void> _fill(WidgetTester tester, String label, String text) async {
  await tester.enterText(
    find.ancestor(of: find.text(label), matching: find.byType(TextField)),
    text,
  );
  await tester.pump();
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.tap(find.text('保存'));
  await tester.pump();
}

/// 等提示浮层自己消失，否则测试结束时会残留定时器
Future<void> _drainToast(WidgetTester tester) =>
    tester.pumpAndSettle(const Duration(seconds: 2));

void main() {
  testWidgets('只填用户名可以保存', (tester) async {
    final saved = await _pumpForm(tester);
    await _fill(tester, '用户名', 'alice');
    await _tapSave(tester);

    expect(saved(), isNotNull);
    expect(saved()!['username'], 'alice');
    expect(saved()!['password'], '');
  });

  testWidgets('只填密码也可以保存（用户名不再必填）', (tester) async {
    final saved = await _pumpForm(tester);
    await _fill(tester, '密码', 's3cret');
    await _tapSave(tester);

    // 回归点：以前这里会被「用户名不能为空」拦下
    expect(saved(), isNotNull);
    expect(saved()!['username'], '');
    expect(saved()!['password'], 's3cret');
  });

  testWidgets('两者都为空时拦截并提示', (tester) async {
    final saved = await _pumpForm(tester);
    await _tapSave(tester);

    expect(saved(), isNull);
    expect(find.textContaining('请至少填写'), findsOneWidget);
    await _drainToast(tester);
  });

  testWidgets('只填备注不足以保存', (tester) async {
    final saved = await _pumpForm(tester);
    await _fill(tester, '用户级备注', '只有备注');
    await _tapSave(tester);

    // 备注不算凭据，避免存下一条没有实际内容的记录
    expect(saved(), isNull);
    await _drainToast(tester);
  });

  testWidgets('纯空格不算有值', (tester) async {
    final saved = await _pumpForm(tester);
    await _fill(tester, '用户名', '   ');
    await _tapSave(tester);

    expect(saved(), isNull);
    await _drainToast(tester);
  });

  testWidgets('requiredKeys 仍然生效（API Key 本身必填）', (tester) async {
    final saved = await _pumpForm(
      tester,
      fields: const [
        InlineField(key: 'key', label: 'API Key', obscure: true),
        InlineField(key: 'note', label: '备注'),
      ],
      requiredKeys: const {'key'},
      requireAnyOf: const {},
    );
    await _tapSave(tester);

    expect(saved(), isNull);
    expect(find.text('API Key不能为空'), findsOneWidget);
    await _drainToast(tester);
  });

  group('打开表单时的自动聚焦', () {
    // 移动端聚焦会连带弹出软键盘遮住半屏，必须等用户主动点输入框
    testWidgets('移动端不自动聚焦首个输入框', (tester) async {
      expect(await _focusedUnder(tester, TargetPlatform.android), isFalse);
    });

    // 桌面端没有软键盘，自动聚焦纯属便利，保持原行为
    testWidgets('桌面端仍自动聚焦首个输入框', (tester) async {
      expect(await _focusedUnder(tester, TargetPlatform.windows), isTrue);
    });
  });
}

/// 在指定平台下渲染表单，返回首个输入框是否拿到焦点。
///
/// Flutter 测试会在用例返回前校验调试变量，因此平台覆盖必须在同一个用例内
/// 用 finally 复位，不能交给 addTearDown（它跑在校验之后）。
Future<bool> _focusedUnder(WidgetTester tester, TargetPlatform platform) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await _pumpForm(tester);
    return _firstFieldFocused(tester);
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// 首个输入框（用户名）是否真的拿到了焦点。
///
/// 断言实际焦点而不是 autofocus 属性：前者才是"会不会弹键盘"的直接原因。
bool _firstFieldFocused(WidgetTester tester) {
  final editable = tester.widget<EditableText>(
    find
        .descendant(
          of: find.ancestor(
              of: find.text('用户名'), matching: find.byType(TextField)),
          matching: find.byType(EditableText),
        )
        .first,
  );
  return editable.focusNode.hasFocus;
}
