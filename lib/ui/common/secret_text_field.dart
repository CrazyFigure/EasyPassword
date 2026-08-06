/// 敏感文本输入框：统一提供显示/隐藏与复制操作。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import 'copy_util.dart';

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
  Widget build(BuildContext context) {
    final obscure = !_visible;
    // 可选参数便于独立复用和测试；应用内默认从全局设置读取。关闭安全键盘时
    // 仍由 Flutter 绘制遮挡字符，只把 Android 输入类型切为普通可见密码，
    // 从而允许用户选择自己的第三方输入法。
    final mobilePlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final useSecureKeyboard = !mobilePlatform ||
        (widget.useSecureKeyboard ??
            context.watch<AppState?>()?.secureKeyboardEnabled ??
            true);
    return TextField(
      controller: widget.controller,
      obscureText: obscure,
      keyboardType: obscure && !useSecureKeyboard
          ? TextInputType.visiblePassword
          : TextInputType.text,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      enableSuggestions: false,
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
