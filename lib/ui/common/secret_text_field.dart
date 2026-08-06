/// 敏感文本输入框：统一提供显示/隐藏与复制操作。
library;

import 'package:flutter/material.dart';

import 'copy_util.dart';

class SecretTextField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration decoration;
  final String copyLabel;
  final bool autofocus;
  final bool enabled;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const SecretTextField({
    super.key,
    required this.controller,
    required this.decoration,
    required this.copyLabel,
    this.autofocus = false,
    this.enabled = true,
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
    return TextField(
      controller: widget.controller,
      obscureText: !_visible,
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
