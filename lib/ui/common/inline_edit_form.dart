/// 内联编辑组件：在卡片原处展开输入框，替代弹窗式编辑
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../state/app_state.dart';
import 'app_toast.dart';
import 'masked_text_controller.dart';
import 'platform_input.dart';
import 'secret_input_actions.dart';

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
  final FutureOr<void> Function(Map<String, String>) onSave;
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
  // 记录用户真正操作过的字段，避免异步初值晚到后覆盖键入或粘贴的内容。
  final Set<String> _changedKeys = {};
  // 数据库写入期间锁住二次提交，避免连续点击产生先发后至的覆盖竞态。
  bool _saving = false;

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
      // 不能用“当前是否为空”判断用户是否编辑：用户可能主动清空旧密码。
      // 只要发生过输入、删除或粘贴，异步初值就不得再覆盖用户的决定。
      if (!_changedKeys.contains(f.key)) {
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

  Future<void> _submit() async {
    if (_saving) return;
    // 必填校验：命中即弹袖珍悬浮提示
    for (final key in widget.requiredKeys) {
      final field = widget.fields.firstWhere((f) => f.key == key);
      if (_submittedValue(field).isEmpty) {
        showAppToast(context, '${field.label}不能为空', kind: ToastKind.error);
        return;
      }
    }
    // 「至少填一个」校验：允许单个字段为空，但不允许整组皆空
    if (widget.requireAnyOf.isNotEmpty) {
      final anyFilled = widget.requireAnyOf
          .map((key) => widget.fields.firstWhere((f) => f.key == key))
          .any((field) => _submittedValue(field).isNotEmpty);
      if (!anyFilled) {
        final labels = widget.requireAnyOf
            .map((key) => widget.fields.firstWhere((f) => f.key == key).label)
            .join('或');
        showAppToast(context, '请至少填写$labels', kind: ToastKind.error);
        return;
      }
    }
    final values = {
      for (final field in widget.fields)
        field.key: _submittedValue(field),
    };
    setState(() => _saving = true);
    try {
      await widget.onSave(values);
    } finally {
      // 保存成功时父级通常会关闭本表单；失败或父级保留表单时恢复操作能力。
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 普通文本去掉无意义的首尾空白；密码等敏感值必须逐字保留。
  ///
  /// 密码可能合法地以空格开头或结尾，粘贴后统一 `trim()` 会悄悄改变凭据，
  /// 最终表现为“明明保存了却无法使用”。敏感字段因此只判断真正的空字符串。
  String _submittedValue(InlineField field) {
    final value = _ctrls[field.key]?.text ?? '';
    return field.obscure ? value : value.trim();
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

    final textField = TextField(
      controller: controller,
      // 自绘遮挡时必须为 false，否则引擎仍会声明密码输入类型。
      obscureText: obscure && !maskInFlutter,
      // 与自绘遮挡及详情页保持同一字符，两条遮挡路径观感一致。
      obscuringCharacter: MaskedTextEditingController.maskCharacter,
      keyboardType: TextInputType.text,
      // 自绘遮挡也允许选择，才能通过长按菜单“全选并粘贴”；菜单本身会过滤
      // 复制、剪切、分享等明文导出动作。
      enableInteractiveSelection: true,
      contextMenuBuilder: f.obscure
          ? buildSecretInputContextMenu
          : buildDefaultTextInputContextMenu,
      enableSuggestions: !f.obscure || requestNormalTextInput,
      // 敏感字段禁止输入法个性化学习，普通字段沿用系统默认行为。
      enableIMEPersonalizedLearning: !f.obscure,
      autocorrect: !f.obscure,
      maxLines: f.obscure ? 1 : f.maxLines,
      // 移动端不抢焦点：自动聚焦会立刻顶起软键盘，遮住半屏表单，
      // 用户还没看清有哪些字段就得先把键盘收起来。桌面端没有这个代价，
      // 保留首个字段自动聚焦以便直接键入。
      autofocus: kAutoFocusOnOpen && f == widget.fields.first,
      readOnly: _saving,
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
      // 输入、删除和系统粘贴都会经过此回调，用于保护用户内容不被异步初值覆盖。
      onChanged: (_) => _changedKeys.add(f.key),
    );
    return f.obscure
        ? protectSecretInputClipboard(child: textField)
        : textField;
  }

  @override
  Widget build(BuildContext context) {
    // 偏好虽然跨设备同步，但只在移动平台改变输入类型，桌面输入行为保持不变。
    final useSecureKeyboard = !isMobileInputPlatform ||
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
                onPressed: _saving ? null : widget.onCancel,
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(64, 36),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
