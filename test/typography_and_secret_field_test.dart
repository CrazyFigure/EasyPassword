import 'package:easypassword/core/theme.dart';
import 'package:easypassword/services/settings_service.dart';
import 'package:easypassword/ui/common/masked_text_controller.dart';
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

  testWidgets('移动端关闭安全键盘后改用自绘遮挡，不再声明密码输入类型', (tester) async {
    // 回归重点：只要 obscureText 为 true，Android 端就会给输入法叠加
    // TYPE_TEXT_VARIATION_PASSWORD，ROM 据此强制系统安全键盘。因此关闭偏好后
    // obscureText 必须为 false，遮挡交给控制器绘制。
    final controller = MaskedTextEditingController(text: 'secret');
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
    expect(field.obscureText, isFalse);
    expect(field.keyboardType, TextInputType.text);
    // 内容仍然不可见，且长按选择被关闭，避免复制到明文。
    expect(controller.maskEnabled, isTrue);
    expect(field.enableInteractiveSelection, isFalse);

    // 点开小眼睛后恢复明文渲染。
    await tester.tap(find.byTooltip('显示测试密码'));
    await tester.pump();
    expect(controller.maskEnabled, isFalse);
  });

  testWidgets('开启安全键盘时沿用系统 obscureText', (tester) async {
    final controller = MaskedTextEditingController(text: 'secret');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SecretTextField(
            controller: controller,
            copyLabel: '测试密码',
            useSecureKeyboard: true,
            decoration: const InputDecoration(labelText: '密码'),
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.obscureText, isTrue);
    expect(controller.maskEnabled, isFalse);
  });

  test('自绘遮挡按字符数铺满圆点，与 obscureText 观感一致', () {
    final controller = MaskedTextEditingController(text: 'secret');
    addTearDown(controller.dispose);
    controller.maskEnabled = true;
    final span = controller.buildTextSpan(
      context: _FakeBuildContext(),
      withComposing: false,
    );
    expect(span.toPlainText(), '•' * 'secret'.length);
  });
}

/// buildTextSpan 在遮挡分支不触碰 context，测试里给个空实现即可。
class _FakeBuildContext extends Fake implements BuildContext {}
