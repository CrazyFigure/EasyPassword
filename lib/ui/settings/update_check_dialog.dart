/// 检测更新弹窗：打开即发起检查，展示 检查中 / 有新版 / 下载中 / 已是最新 / 出错 状态。
/// 新版本信息来自 GitHub Releases；Windows 支持应用内直接下载并启动安装程序，
/// 其余平台或拿不到安装包直链时回退为跳转 Release 页面手动下载。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../services/update_service.dart';
import '../center_dialog.dart';

/// 弹出检测更新弹窗，检查完成后原地更新内容。
Future<void> showUpdateCheckDialog(BuildContext context) {
  return showCenterDialog<void>(
    context: context,
    maxWidth: 380,
    builder: (_) => const _UpdateCheckDialog(),
  );
}

class _UpdateCheckDialog extends StatefulWidget {
  const _UpdateCheckDialog();

  @override
  State<_UpdateCheckDialog> createState() => _UpdateCheckDialogState();
}

class _UpdateCheckDialogState extends State<_UpdateCheckDialog> {
  final UpdateService _service = UpdateService();
  bool _checking = true;
  UpdateCheckResult? _result;
  String? _errorText;

  // 下载状态
  bool _downloading = false;
  int _downloadedBytes = 0;
  int? _totalBytes;
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _checking = true;
      _errorText = null;
    });
    try {
      final result = await _service.check();
      if (!mounted) return;
      setState(() {
        _result = result;
        _checking = false;
      });
    } on UpdateCheckException catch (e) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _errorText = _translateError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _errorText = '检查更新时出现未知错误，请稍后重试';
      });
    }
  }

  /// 下载并安装更新包。下载到临时目录，完成后拉起安装器。
  Future<void> _downloadAndInstall() async {
    final result = _result;
    if (result == null || !result.canInstallInApp) return;

    setState(() {
      _downloading = true;
      _downloadedBytes = 0;
      _totalBytes = result.installerSize;
      _downloadError = null;
    });

    try {
      final fileName = result.installerAssetName ??
          (Platform.isWindows ? 'EasyPassword-Setup.exe' : 'EasyPassword.apk');
      final savePath = await UpdateService.resolveDownloadPath(fileName);

      final path = await _service.downloadInstaller(
        downloadUrl: result.installerDownloadUrl!,
        savePath: savePath,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _downloadedBytes = received;
            _totalBytes = total;
          });
        },
        isCancelled: () => !mounted || !_downloading,
      );

      if (!mounted) return;

      // 下载完成后交给平台安装器；Windows 辅助进程会校验目标版本并负责重新拉起应用。
      await _service.launchInstaller(
        path,
        expectedVersion: result.latestVersion,
      );

      // Android 交接成功后关闭弹窗；Windows 正常更新时旧进程已由安装器关闭。
      if (mounted) Navigator.pop(context);
    } on UpdateDownloadException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadError = _translateDownloadError(e);
      });
    } on UpdateInstallException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadError = _translateInstallError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadError = '操作失败: $e';
      });
    }
  }

  /// 将更新检查错误码翻译为中文文案（对齐 MyTerminal 的错误分类语义）
  String _translateError(UpdateCheckException e) {
    switch (e.code) {
      case 'network':
        return '无法连接 GitHub，请检查网络连接或代理设置后重试';
      case 'rate_limited':
        return 'GitHub API 访问过于频繁（已被限流），请稍后再试';
      case 'forbidden':
        return '请求被 GitHub 拒绝（可能是代理节点被风控），已尝试直连仍失败，请更换代理或稍后重试';
      case 'http_status':
        return 'GitHub 服务异常（HTTP ${e.detail}），请稍后重试';
      case 'parse':
        return '更新信息解析失败，请稍后重试';
      default:
        return '检查更新失败，请稍后重试';
    }
  }

  String _translateDownloadError(UpdateDownloadException e) {
    switch (e.code) {
      case 'network':
        return '网络连接失败，请检查网络后重试';
      case 'http_status':
        return '下载失败: HTTP ${e.detail}';
      case 'io':
        return '文件写入失败，请检查磁盘空间';
      case 'cancelled':
        return '下载已取消';
      default:
        return '下载失败: ${e.detail}';
    }
  }

  String _translateInstallError(UpdateInstallException e) {
    switch (e.code) {
      case 'missing_file':
        return '安装包文件丢失，请重新下载';
      case 'launch_failed':
        return '启动安装程序失败${e.detail.isNotEmpty ? ': ${e.detail}' : ''}';
      case 'permission_denied':
        return Platform.isAndroid
            ? '需要授权"安装未知应用"后重试，已为你打开设置页'
            : '权限不足，无法启动安装程序';
      case 'unsupported_platform':
        return '当前平台不支持应用内安装';
      default:
        return '安装失败: ${e.detail}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题行
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
                child: const Icon(Icons.system_update_alt,
                    size: 20, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              const Text('检查更新',
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
          const SizedBox(height: 18),
          // 状态区
          if (_checking)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Column(
                children: [
                  CircularProgressIndicator(strokeWidth: 2.5),
                  SizedBox(height: 14),
                  Text('正在检查更新...',
                      style:
                          TextStyle(fontSize: 13, color: AppColors.textWeak)),
                ],
              ),
            )
          else if (_downloading)
            _DownloadingBlock(
              downloadedBytes: _downloadedBytes,
              totalBytes: _totalBytes,
              onCancel: () => setState(() => _downloading = false),
            )
          else if (_downloadError != null)
            _StatusBlock(
              icon: Icons.error_outline,
              iconColor: AppColors.danger,
              message: _downloadError!,
              action: FilledButton(
                onPressed: _downloadAndInstall,
                child: const Text('重试'),
              ),
            )
          else if (_errorText != null)
            _StatusBlock(
              icon: Icons.error_outline,
              iconColor: AppColors.danger,
              message: _errorText!,
              action: FilledButton(
                onPressed: _run,
                child: const Text('重试'),
              ),
            )
          else if (_result != null && _result!.updateAvailable)
            _StatusBlock(
              icon: Icons.new_releases_outlined,
              iconColor: AppColors.primary,
              message:
                  '发现新版本：v${_result!.currentVersion} → v${_result!.latestVersion}',
              detail: _result!.releaseName.isNotEmpty
                  ? _result!.releaseName
                  : null,
              action: _result!.canInstallInApp
                  ? FilledButton.icon(
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('下载并安装'),
                      onPressed: _downloadAndInstall,
                    )
                  : FilledButton.icon(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('前往 GitHub 下载'),
                      onPressed: () =>
                          launchUrl(Uri.parse(_result!.releaseUrl),
                              mode: LaunchMode.externalApplication),
                    ),
            )
          else if (_result != null)
            _StatusBlock(
              icon: Icons.check_circle_outline,
              iconColor: AppColors.success,
              message: '当前已是最新版本（v${_result!.currentVersion}）',
              action: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ),
        ],
      ),
    );
  }
}

/// 下载进度展示块：进度条 + 字节数 + 取消按钮
class _DownloadingBlock extends StatelessWidget {
  final int downloadedBytes;
  final int? totalBytes;
  final VoidCallback onCancel;

  const _DownloadingBlock({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final total = totalBytes;
    final hasTotal = total != null && total > 0;
    final percent = hasTotal ? (downloadedBytes / total).clamp(0.0, 1.0) : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.download, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hasTotal
                          ? '下载中 ${(percent * 100).toStringAsFixed(0)}%'
                          : '正在下载...',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: hasTotal ? percent : null,
                  minHeight: 6,
                  backgroundColor: AppColors.divider,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              if (hasTotal) ...[
                const SizedBox(height: 6),
                Text(
                  '${_formatBytes(downloadedBytes)} / ${_formatBytes(total)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textWeak,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        TextButton(
          onPressed: onCancel,
          child: const Text('取消'),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 状态展示块：图标 + 主文案 + 可选副文案 + 底部操作按钮
class _StatusBlock extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String message;
  final String? detail;
  final Widget action;

  const _StatusBlock({
    required this.icon,
    required this.iconColor,
    required this.message,
    this.detail,
    required this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 22, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMain)),
                    if (detail != null && detail!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(detail!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textWeak)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        action,
      ],
    );
  }
}
