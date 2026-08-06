/// 支持在 Flutter 层自绘遮挡的输入控制器。
library;

import 'package:flutter/widgets.dart';

/// 遮挡渲染、但不向系统声明「密码输入类型」的文本控制器。
///
/// 背景：只要把 `TextField.obscureText` 置为 true，Flutter 的 Android 端
/// `TextInputPlugin.inputTypeFromTextInputType()` 就会无条件给 EditorInfo
/// 叠加 `TYPE_TEXT_VARIATION_PASSWORD`：
///
/// ```java
/// if (obscureText) {
///   textType |= InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS;
///   textType |= InputType.TYPE_TEXT_VARIATION_PASSWORD;
/// }
/// ```
///
/// 国产 ROM 与多数第三方输入法都按 `inputType & TYPE_MASK_VARIATION` 是否
/// 落在密码类上来判定密码框，命中即强制切换系统安全键盘。仅把 keyboardType
/// 改成 `visiblePassword` 无法规避——`0x90 | 0x80` 仍等于 `0x90`，依旧是密码
/// variation。
///
/// 因此「关闭安全键盘」时必须让 obscureText 保持 false，输入法才会拿到普通
/// 文本类型；遮挡改由本控制器在 [buildTextSpan] 中完成——`EditableText` 只有
/// 在 obscureText 为 false 时才会调用控制器的这个钩子。
class MaskedTextEditingController extends TextEditingController {
  MaskedTextEditingController({super.text});

  /// 与 `TextField.obscuringCharacter` 的默认值保持一致，切换开关前后观感不变。
  static const String maskCharacter = '•';

  /// 是否由本控制器绘制遮挡；由使用方在 build 中按当前显隐与键盘偏好设置。
  bool maskEnabled = false;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!maskEnabled) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    // 与框架 obscureText 的实现一致按 UTF-16 长度铺满遮挡字符，
    // 保证开关切换前后圆点数量不发生变化。
    return TextSpan(style: style, text: maskCharacter * text.length);
  }
}
