/// 内联编辑组件：在卡片原处展开输入框，替代弹窗式编辑
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// 内联编辑用的单个字段定义
class InlineField {
  final String key;
  final String label;
  final String hint;
  final String initial;

  /// 敏感字段：默认遮挡，但提供小眼睛切换显示。
  /// 与 [resolveInitial] 搭配可实现「编辑时带出原值」。
  final bool obscure;
  final int maxLines;

  /// 异步取初值（用于需要解密后才能回填的密码 / API Key）。
  /// 非空时优先于 [initial]，解密完成后自动填入输入框。
  final Future<String> Function()? resolveInitial;

  const InlineField({
    required this.key,
    required this.label,
    this.hint = '',
    this.initial = '',
    this.obscure = false,
    this.maxLines = 1,
    this.resolveInitial,
  });
}

/// 就地编辑表单：若干输入框 + 取消/保存。
///
/// 由父级在「编辑态」时替换原展示卡片渲染，视觉上就是卡片本身变成了可编辑状态。
/// [onSave] 收到各字段 key -> 文本值；[requiredKeys] 中的字段为空时拦截并提示。
class InlineEditForm extends StatefulWidget {
  final String title;
  final List<InlineField> fields;
  final Set<String> requiredKeys;
  final ValueChanged<Map<String, String>> onSave;
  final VoidCallback onCancel;

  const InlineEditForm({
    super.key,
    required this.title,
    required this.fields,
    required this.onSave,
    required this.onCancel,
    this.requiredKeys = const {},
  });

  @override
  State<InlineEditForm> createState() => _InlineEditFormState();
}

class _InlineEditFormState extends State<InlineEditForm> {
  late final Map<String, TextEditingController> _ctrls;
  // 敏感字段的显示状态：key -> 是否明文可见
  late final Map<String, bool> _visible;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrls = {
      for (final f in widget.fields)
        f.key: TextEditingController(text: f.initial),
    };
    _visible = {
      for (final f in widget.fields.where((f) => f.obscure)) f.key: false,
    };
    _resolveInitials();
  }

  /// 异步回填需要解密的字段原值
  Future<void> _resolveInitials() async {
    for (final f in widget.fields) {
      final resolve = f.resolveInitial;
      if (resolve == null) continue;
      final value = await resolve();
      if (!mounted) return;
      // 用户可能已抢先输入，此时不覆盖
      if (_ctrls[f.key]!.text.isEmpty) {
        _ctrls[f.key]!.text = value;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    // 必填校验：命中即就地红字提示，不弹 SnackBar
    for (final key in widget.requiredKeys) {
      if ((_ctrls[key]?.text.trim() ?? '').isEmpty) {
        final field = widget.fields.firstWhere((f) => f.key == key);
        setState(() => _error = '${field.label}不能为空');
        return;
      }
    }
    widget.onSave({
      for (final e in _ctrls.entries) e.key: e.value.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        // 编辑态用主色描边，与只读卡片区分
        border: Border.all(color: AppColors.primary, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textWeak),
          ),
          const SizedBox(height: 10),
          for (final f in widget.fields) ...[
            TextField(
              controller: _ctrls[f.key],
              // 敏感字段默认遮挡，可用行尾小眼睛切换
              obscureText: f.obscure && !(_visible[f.key] ?? false),
              maxLines: f.obscure ? 1 : f.maxLines,
              autofocus: f == widget.fields.first,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: f.label,
                hintText: f.hint,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                suffixIcon: f.obscure
                    ? IconButton(
                        icon: Icon(
                          (_visible[f.key] ?? false)
                              ? Icons.visibility
                              : Icons.visibility_off,
                          size: 18,
                          color: AppColors.textWeak,
                        ),
                        tooltip: (_visible[f.key] ?? false) ? '隐藏' : '显示',
                        onPressed: () => setState(
                            () => _visible[f.key] = !(_visible[f.key] ?? false)),
                      )
                    : null,
              ),
              // 单行字段回车即保存
              textInputAction:
                  f.maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
              onSubmitted: f.maxLines > 1 ? null : (_) => _submit(),
            ),
            const SizedBox(height: 10),
          ],
          if (_error != null) ...[
            Text(_error!,
                style: const TextStyle(fontSize: 12, color: AppColors.danger)),
            const SizedBox(height: 8),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.onCancel,
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 36),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _submit,
                child: const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
