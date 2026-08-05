/// 文件夹编辑弹窗：设置名称与颜色，新建与重命名共用
library;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/folder_palette.dart';
import 'center_dialog.dart';

/// 文件夹编辑结果：名称 + 颜色（颜色为 null 表示用主题默认色）
class FolderEditResult {
  final String name;
  final int? color;
  const FolderEditResult(this.name, this.color);
}

/// 弹出文件夹编辑框。
/// [initialName] 非空表示重命名，弹窗标题与按钮文案随之变化。
/// 取消返回 null。
Future<FolderEditResult?> showFolderEditDialog({
  required BuildContext context,
  String? initialName,
  int? initialColor,
}) {
  return showCenterDialog<FolderEditResult>(
    context: context,
    maxWidth: 380,
    builder: (_) => _FolderEditDialog(
      initialName: initialName,
      initialColor: initialColor,
    ),
  );
}

class _FolderEditDialog extends StatefulWidget {
  final String? initialName;
  final int? initialColor;

  const _FolderEditDialog({this.initialName, this.initialColor});

  @override
  State<_FolderEditDialog> createState() => _FolderEditDialogState();
}

class _FolderEditDialogState extends State<_FolderEditDialog> {
  late final TextEditingController _ctrl;
  late int? _color;
  String? _error;

  bool get _isRename => widget.initialName != null;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialName ?? '');
    // 新建时默认选中调色板第一个颜色，避免"没选色"的空状态
    _color = widget.initialColor ?? FolderPalette.colors.first.toARGB32();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _ctrl.text.trim();
    // 就地红字提示，与内联编辑表单的校验风格一致
    if (name.isEmpty) {
      setState(() => _error = '文件夹名称不能为空');
      return;
    }
    Navigator.pop(context, FolderEditResult(name, _color));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行：图标随所选颜色实时变化，充当预览
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: FolderPalette.bgOf(_color),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.folder_rounded,
                    size: 20, color: FolderPalette.colorOf(_color)),
              ),
              const SizedBox(width: 10),
              Text(_isRename ? '编辑文件夹' : '新建文件夹',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain)),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '文件夹名称',
              hintText: '例如：工作、常用、财务',
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(fontSize: 12, color: AppColors.danger)),
          ],
          const SizedBox(height: 18),
          const Text('文件夹颜色',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textWeak)),
          const SizedBox(height: 10),
          // 色板：换行铺排，选中项加深色描边与对勾
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final c in FolderPalette.colors)
                _ColorDot(
                  color: c,
                  selected: _color == c.toARGB32(),
                  onTap: () => setState(() => _color = c.toARGB32()),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(88, 44)),
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
                onPressed: _submit,
                child: Text(_isRename ? '保存' : '创建'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单个可选色块
class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          // 选中时用白色内圈 + 同色外环强调
          border: Border.all(
            color: selected ? Colors.white : Colors.transparent,
            width: selected ? 3 : 0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.55),
                    blurRadius: 0,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        child: selected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}
