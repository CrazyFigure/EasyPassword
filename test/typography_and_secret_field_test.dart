import 'package:easypassword/core/theme.dart';
import 'package:easypassword/services/settings_service.dart';
import 'package:easypassword/ui/common/secret_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('字号选项标签唯一且兼容旧数值', () {
    // 防止再次出现两个“跟随系统”，同时保障已保存的旧版本数值可平滑升级。
    final labels = FontSizeMode.values.map((mode) => mode.label).toSet();
    expect(labels.length, FontSizeMode.values.length);
    expect(FontSizeMode.fromStored('1.0'), FontSizeMode.system);
    expect(FontSizeMode.fromStored('0.85'), FontSizeMode.small);
    expect(FontSizeMode.fromStored('standard'), FontSizeMode.standard);
  });

  testWidgets('小字号通过 MediaQuery 缩放不会触发 TextStyle 断言', (tester) async {
    // 回归截图中的 fontSizeFactor 断言：主题本身不再修改 TextTheme 字号。
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: const TextScaler.linear(0.85)),
            child: child!,
          );
        },
        home: const Scaffold(body: Text('小字号预览')),
      ),
    );

    expect(find.text('小字号预览'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('敏感输入框同时提供复制和显示操作', (tester) async {
    final controller = TextEditingController(text: 'secret');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SecretTextField(
            controller: controller,
            copyLabel: '测试密码',
            decoration: const InputDecoration(labelText: '密码'),
          ),
        ),
      ),
    );

    expect(find.byTooltip('复制测试密码'), findsOneWidget);
    expect(find.byTooltip('显示测试密码'), findsOneWidget);
    await tester.tap(find.byTooltip('显示测试密码'));
    await tester.pump();
    expect(find.byTooltip('隐藏测试密码'), findsOneWidget);
  });

  testWidgets('移动端关闭安全键盘后仍遮挡内容并允许普通输入法', (tester) async {
    final controller = TextEditingController(text: 'secret');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SecretTextField(
            controller: controller,
            copyLabel: '测试密码',
            useSecureKeyboard: false,
            decoration: const InputDecoration(labelText: '密码'),
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
    expect(field.keyboardType, TextInputType.visiblePassword);
  });
}
