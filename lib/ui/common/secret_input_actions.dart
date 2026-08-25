/// 敏感输入框的剪贴板交互：允许粘贴与全选，但阻止从输入框导出明文。
library;

import 'package:flutter/material.dart';

/// 复用 `TextField` 的平台默认菜单，供同一动态表单中的普通字段使用。
Widget buildDefaultTextInputContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  if (SystemContextMenu.isSupportedByField(editableTextState)) {
    return SystemContextMenu.editableText(editableTextState: editableTextState);
  }
  return AdaptiveTextSelectionToolbar.editableText(
    editableTextState: editableTextState,
  );
}

/// 构建敏感字段的长按菜单。
///
/// Flutter 自绘遮挡要求 `obscureText=false`，框架因此会误以为当前是普通文本，
/// 默认提供复制、剪切、分享和网页搜索。这些动作都可能泄露控制器中的真实明文；
/// 此处只保留粘贴与全选，既支持用新密码整体替换旧密码，也不暴露导出入口。
Widget buildSecretInputContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
) {
  final safeItems = editableTextState.contextMenuButtonItems
      .where((item) {
        return item.type == ContextMenuButtonType.paste ||
            item.type == ContextMenuButtonType.selectAll;
      })
      .toList(growable: false);
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: safeItems,
  );
}

/// 禁止敏感字段通过键盘复制或剪切明文，同时保留系统粘贴快捷键。
///
/// 长按菜单由 [buildSecretInputContextMenu] 约束；这里补齐硬件键盘快捷键路径。
/// 应用已有独立的显式复制按钮，用户确需复制时仍可通过该入口完成。
Widget protectSecretInputClipboard({required Widget child}) {
  return Actions(
    actions: <Type, Action<Intent>>{CopySelectionTextIntent: DoNothingAction()},
    child: child,
  );
}
