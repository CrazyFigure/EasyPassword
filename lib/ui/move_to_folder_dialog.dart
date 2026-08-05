/// 「移动到文件夹」选择弹窗：批量把条目移入某个文件夹，或移出到上一级
library;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/folder_palette.dart';
import '../models/folder.dart';
import 'center_dialog.dart';

/// 移动目标：[folderId] 为 null 表示移到根目录（移出文件夹）
class MoveTarget {
  final String? folderId;
  const MoveTarget(this.folderId);
}

/// 弹出文件夹选择框。
/// [allowRoot] 为 true 时额外提供「移出到上一级」选项（文件夹内页用）。
/// 取消返回 null。
Future<MoveTarget?> showMoveToFolderDialog({
  required BuildContext context,
  required List<Folder> folders,
  bool allowRoot = false,
  String? currentFolderId,
}) {
  return showCenterDialog<MoveTarget>(
    context: context,
    maxWidth: 380,
    builder: (_) => _MoveToFolderDialog(
      folders: folders,
      allowRoot: allowRoot,
      currentFolderId: currentFolderId,
    ),
  );
}

class _MoveToFolderDialog extends StatelessWidget {
  final List<Folder> folders;
  final bool allowRoot;
  final String? currentFolderId;

  const _MoveToFolderDialog({
    required this.folders,
    required this.allowRoot,
    this.currentFolderId,
  });

  @override
  Widget build(BuildContext context) {
    // 排除当前所在文件夹：移到自己所在的位置没有意义
    final targets =
        folders.where((f) => f.id != currentFolderId).toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primaryLightBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.drive_file_move_outline,
                    size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              const Text('移动到文件夹',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: AppColors.textWeak),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (allowRoot) ...[
            _TargetRow(
              icon: Icons.north_west,
              title: '移出到上一级',
              subtitle: '不放入任何文件夹',
              onTap: () => Navigator.pop(context, const MoveTarget(null)),
            ),
            const SizedBox(height: 10),
          ],
          // 无可选目标时给出明确提示，而不是空白弹窗
          if (targets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text('还没有其他文件夹，请先在列表页新建',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textWeak)),
            )
          else
            // 文件夹较多时可滚动，避免弹窗被撑破
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: targets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _TargetRow(
                  icon: Icons.folder_rounded,
                  title: targets[i].name,
                  // 目标行图标沿用该文件夹的自定义颜色，便于辨认
                  iconColor: FolderPalette.colorOf(targets[i].color),
                  onTap: () =>
                      Navigator.pop(context, MoveTarget(targets[i].id)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单个可选目标行
class _TargetRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor; // 文件夹自定义色；null 用主色
  final VoidCallback onTap;

  const _TargetRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppColors.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMain),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textWeak)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
