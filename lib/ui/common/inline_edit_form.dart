/// 内联编辑组件：在卡片原处展开输入框，替代弹窗式编辑
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../state/app_state.dart';
import 'app_toast.dart';
import 'masked_text_controller.dart';

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
///
/// [requireAnyOf] 用于「其中至少一个有值」的场景：例如网站账号的用户名与密码
/// 都允许单独为空，但不能两者皆空而存下一条空记录。
class InlineEditForm extends StatefulWidget {
  final String title;
  final List<InlineField> fields;
  final Set<String> requiredKeys;

  /// 至少需填其中一个的字段 key；为空集合表示不做此校验
  final Set<String> requireAnyOf;
  final ValueChanged<Map<String, String>> onSave;
  final VoidCallback onCancel;

  const InlineEditForm({
    super.key,
    required this.title,
    required this.fields,
    required this.onSave,
    required this.onCancel,
    this.requiredKeys = const {},
    this.requireAnyOf = const {},
  });

  @override
  State<InlineEditForm> createState() => _InlineEditFormState();
}

class _InlineEditFormState extends State<InlineEditForm> {
  // 敏感字段关闭安全键盘时需要在 Flutter 层自绘遮挡，因此统一用支持遮挡的控制器。
  late final Map<String, MaskedTextEditingController> _ctrls;
  // 敏感字段的显示状态：key -> 是否明文可见
  late final Map<String, bool> _visible;

  @override
  void initState() {
    super.initState();
    _ctrls = {
      for (final f in widget.fields)
        f.key: MaskedTextEditingController(text: f.initial),
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
    // 必填校验：命中即弹袖珍悬浮提示
    for (final key in widget.requiredKeys) {
      if ((_ctrls[key]?.text.trim() ?? '').isEmpty) {
        final field = widget.fields.firstWhere((f) => f.key == key);
        showAppToast(context, '${field.label}不能为空', kind: ToastKind.error);
        return;
      }
    }
    // 「至少填一个」校验：允许单个字段为空，但不允许整组皆空
    if (widget.requireAnyOf.isNotEmpty) {
      final anyFilled = widget.requireAnyOf
          .any((key) => (_ctrls[key]?.text.trim() ?? '').isNotEmpty);
      if (!anyFilled) {
        final labels = widget.requireAnyOf
            .map((key) => widget.fields.firstWhere((f) => f.key == key).label)
            .join('或');
        showAppToast(context, '请至少填写$labels', kind: ToastKind.error);
        return;
      }
    }
    widget.onSave({
      for (final e in _ctrls.entries) e.key: e.value.text.trim(),
    });
  }

  /// 渲染单个字段。敏感字段默认遮挡，同时禁用联想和自动纠错避免敏感值泄漏。
  ///
  /// 关闭安全键盘时不能再依赖 obscureText——Android 端只要收到它就会给输入法
  /// 声明密码输入类型，ROM 据此强制切换系统安全键盘。此时改由控制器自绘圆点，
  /// 输入类型保持普通文本，用户选择的第三方输入法才能被调起。
  Widget _buildField(InlineField f, bool useSecureKeyboard) {
    final controller = _ctrls[f.key]!;
    final revealed = _visible[f.key] ?? false;
    final obscure = f.obscure && !revealed;
    final maskInFlutter = obscure && !useSecureKeyboard;
    // Flutter Android 引擎会把「禁用建议」映射成 visiblePassword 输入类型；
    // vivo 仍会将其识别为密码框。关闭安全键盘时需允许 suggestions 配置，
    // 才能得到普通文本 EditorInfo，实际的密码学习由独立参数继续禁止。
    final requestNormalTextInput = f.obscure && !useSecureKeyboard;
    controller.maskEnabled = maskInFlutter;

    return TextField(
      controller: controller,
      // 自绘遮挡时必须为 false，否则引擎仍会声明密码输入类型。
      obscureText: obscure && !maskInFlutter,
      // 与自绘遮挡及详情页保持同一字符，两条遮挡路径观感一致。
      obscuringCharacter: MaskedTextEditingController.maskCharacter,
      keyboardType: TextInputType.text,
      // 对齐 obscureText 默认关闭选择的行为，避免长按选中后复制到明文。
      enableInteractiveSelection: maskInFlutter ? false : null,
      enableSuggestions: !f.obscure || requestNormalTextInput,
      // 敏感字段禁止输入法个性化学习，普通字段沿用系统默认行为。
      enableIMEPersonalizedLearning: !f.obscure,
      autocorrect: !f.obscure,
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
                  revealed ? Icons.visibility : Icons.visibility_off,
                  size: 18,
                  color: AppColors.textWeak,
                ),
                tooltip: revealed ? '隐藏' : '显示',
                onPressed: () => setState(() => _visible[f.key] = !revealed),
              )
            : null,
      ),
      // 单行字段回车即保存
      textInputAction:
          f.maxLines > 1 ? TextInputAction.newline : TextInputAction.done,
      onSubmitted: f.maxLines > 1 ? null : (_) => _submit(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 偏好虽然跨设备同步，但只在移动平台改变输入类型，桌面输入行为保持不变。
    final mobilePlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final useSecureKeyboard = !mobilePlatform ||
        (context.watch<AppState?>()?.secureKeyboardEnabled ?? true);
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
            _buildField(f, useSecureKeyboard),
            const SizedBox(height: 10),
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
