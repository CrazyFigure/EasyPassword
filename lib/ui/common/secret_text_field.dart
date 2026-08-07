/// 敏感文本输入框：统一提供显示/隐藏与复制操作。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import 'copy_util.dart';
import 'masked_text_controller.dart';

class SecretTextField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final String copyLabel;
  final bool autofocus;
  final bool enabled;
  final bool? useSecureKeyboard;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const SecretTextField({
    super.key,
    required this.controller,
    required this.decoration,
    required this.copyLabel,
    this.autofocus = false,
    this.enabled = true,
    this.useSecureKeyboard,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  State<SecretTextField> createState() => _SecretTextFieldState();
}

class _SecretTextFieldState extends State<SecretTextField> {
  bool _visible = false;

  @override
  void dispose() {
    // 控制器由外部持有并可能在别处复用，离开时复位遮挡标记避免残留。
    final controller = widget.controller;
    if (controller is MaskedTextEditingController) {
      controller.maskEnabled = false;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final obscure = !_visible;
    // 可选参数便于独立复用和测试；应用内默认从全局设置读取。
    final mobilePlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final useSecureKeyboard = !mobilePlatform ||
        (widget.useSecureKeyboard ??
            context.watch<AppState?>()?.secureKeyboardEnabled ??
            true);

    // 关闭安全键盘时改由 Flutter 自绘圆点：只有 obscureText 保持 false，
    // Android 才会把输入类型报成普通文本，第三方输入法才能被正常调起。
    final controller = widget.controller;
    assert(
      useSecureKeyboard || controller is MaskedTextEditingController,
      'SecretTextField 关闭安全键盘时需配合 MaskedTextEditingController，'
      '否则只能退回系统安全键盘',
    );
    // 控制器不支持自绘时宁可继续用系统安全键盘，也不能让密码明文显示。
    final maskInFlutter = obscure &&
        !useSecureKeyboard &&
        controller is MaskedTextEditingController;
    // Flutter Android 引擎会在 enableSuggestions=false 时强制叠加
    // TYPE_TEXT_VARIATION_VISIBLE_PASSWORD，即使 obscureText 已经关闭，vivo
    // 仍会据此拉起安全键盘。关闭安全键盘后必须把该值设为 true，才能让
    // EditorInfo 保持 TYPE_TEXT_VARIATION_NORMAL；密码学习则由下方独立关闭。
    final requestNormalTextInput =
        !useSecureKeyboard && controller is MaskedTextEditingController;
    if (controller is MaskedTextEditingController) {
      controller.maskEnabled = maskInFlutter;
    }

    return TextField(
      controller: controller,
      // 自绘遮挡时必须为 false，否则引擎仍会声明密码输入类型。
      obscureText: obscure && !maskInFlutter,
      // 与自绘遮挡及详情页保持同一字符，两条遮挡路径观感一致。
      obscuringCharacter: MaskedTextEditingController.maskCharacter,
      keyboardType: TextInputType.text,
      // 对齐 obscureText 默认关闭选择的行为，避免长按选中后复制到明文；
      // 其余情况传 null 交还框架默认值。
      enableInteractiveSelection: maskInFlutter ? false : null,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      enableSuggestions: requestNormalTextInput,
      // 无论选择哪种键盘都禁止 IME 学习密码，避免普通输入法保存敏感内容。
      enableIMEPersonalizedLearning: false,
      autocorrect: false,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      decoration: widget.decoration.copyWith(
        // 两个动作始终采用同一顺序：先复制，再显示/隐藏。
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CopyIconButton(
              label: widget.copyLabel,
              onResolve: () async => widget.controller.text,
            ),
            IconButton(
              tooltip:
                  _visible ? '隐藏${widget.copyLabel}' : '显示${widget.copyLabel}',
              onPressed: () => setState(() => _visible = !_visible),
              icon: Icon(
                _visible ? Icons.visibility : Icons.visibility_off,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
