/// 明文导入导出页：本地明文备份与恢复，不加密也不上传。
///
/// 风险提示前置：文件内容等同于全部密码原文，界面必须明确强调。
/// 导入提供增量与覆盖两种模式，覆盖模式按危险操作处理。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../services/plain_transfer_service.dart';
import '../../state/app_state.dart';
import '../common/app_toast.dart';
import '../common/confirm_dialog.dart';

class PlainTransferPage extends StatefulWidget {
  const PlainTransferPage({super.key});

  @override
  State<PlainTransferPage> createState() => _PlainTransferPageState();
}

class _PlainTransferPageState extends State<PlainTransferPage> {
  /// 导入来源：文件路径或直接粘贴文本
  late final TextEditingController _pathCtrl;
  late final TextEditingController _textCtrl;
  String? _exportedPath;
  bool _exporting = false;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _pathCtrl = TextEditingController();
    _textCtrl = TextEditingController();
    _loadDefaultPath();
  }

  /// 预填默认导出路径，用户可改成任意本机文件位置
  Future<void> _loadDefaultPath() async {
    final path = await context.read<AppState>().plainExportFilePath();
    if (!mounted) return;
    setState(() => _pathCtrl.text = path);
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final path = await context.read<AppState>().exportPlainFile();
      if (!mounted) return;
      setState(() {
        _exportedPath = path;
        // 导出后同步到导入路径，方便在另一端照抄或本机直接回滚
        _pathCtrl.text = path;
      });
      showAppToast(context, '明文备份已导出', kind: ToastKind.success);
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '导出失败：${_message(error)}', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 执行导入。[fromText] 为 true 时使用文本框内容，否则读取路径指定的文件。
  Future<void> _import(PlainImportMode mode, {required bool fromText}) async {
    final isReplace = mode == PlainImportMode.replace;
    final confirmed = await showConfirmDialog(
      context: context,
      title: isReplace ? '覆盖导入' : '增量导入',
      content: isReplace
          ? '当前设备的密码与 API Key 将被备份内容完整替换，备份中不存在的条目会被删除。'
              '删除会同步到其他设备。确定继续吗？'
          : '备份中的条目会新增或更新到当前设备，本机其他数据保持不变。确定继续吗？',
      confirmText: isReplace ? '继续覆盖' : '继续导入',
      isDangerous: isReplace,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _importing = true);
    final state = context.read<AppState>();
    try {
      final result = fromText
          ? await state.importPlainText(_textCtrl.text, mode: mode)
          : await state.importPlainFile(mode: mode, path: _pathCtrl.text);
      if (!mounted) return;
      showAppToast(context, '导入完成，${result.summary}',
          kind: ToastKind.success, duration: const Duration(seconds: 3));
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '导入失败：${_message(error)}',
          kind: ToastKind.error, duration: const Duration(seconds: 3));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String _message(Object error) => error is PlainImportException
      ? error.message
      : error.toString().replaceFirst('Exception: ', '');

  Widget _spinner(Color color) => SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );

  @override
  Widget build(BuildContext context) {
    final busy = _exporting || _importing;
    return Scaffold(
      appBar: AppBar(title: const Text('明文导入导出')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildWarning(),
                  const SizedBox(height: 20),
                  const _SectionTitle('导出'),
                  const SizedBox(height: 10),
                  _buildExportCard(busy),
                  const SizedBox(height: 22),
                  const _SectionTitle('导入'),
                  const SizedBox(height: 10),
                  _buildImportCard(busy),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarning() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: AppColors.danger),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '明文备份不加密，文件内容等同于全部密码与 API Key 原文。'
              '只会写入本机，不会上传到 WebDAV，请妥善保管并在用完后及时删除。',
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: AppColors.textMain),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportCard(bool busy) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '导出为可读 JSON，含全部未删除的密码与 API Key，可用文本编辑器直接修改后再导入。',
            style: TextStyle(
                fontSize: 13, height: 1.5, color: AppColors.textSecondary),
          ),
          if (_exportedPath != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryLightBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('已导出到',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMain)),
                  const SizedBox(height: 4),
                  SelectableText(
                    _exportedPath!,
                    style: const TextStyle(
                        fontSize: 12, height: 1.4, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            await Clipboard.setData(
                                ClipboardData(text: _exportedPath!));
                            if (!mounted) return;
                            showAppToast(context, '路径已复制',
                                kind: ToastKind.success);
                          },
                    icon: const Icon(Icons.copy_all_outlined, size: 16),
                    label: const Text('复制路径'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : _export,
            icon: _exporting
                ? _spinner(Colors.white)
                : const Icon(Icons.file_download_outlined, size: 18),
            label: const Text('导出明文备份'),
          ),
        ],
      ),
    );
  }

  Widget _buildImportCard(bool busy) {
    final hasText = _textCtrl.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '增量导入只新增与更新，保留本机其他数据；覆盖导入以备份为唯一事实，'
            '会删除备份中不存在的条目。两种方式的结果都会同步到其他设备。',
            style: TextStyle(
                fontSize: 13, height: 1.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pathCtrl,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: '备份文件路径',
              helperText: '默认指向本机导出位置，也可填写其他设备拷来的文件路径',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _import(PlainImportMode.merge, fromText: false),
                  icon: const Icon(Icons.merge_outlined, size: 18),
                  label: const Text('增量导入'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => _import(PlainImportMode.replace, fromText: false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  icon: const Icon(Icons.published_with_changes, size: 18),
                  label: const Text('覆盖导入'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 16),
          const Text(
            '或直接粘贴备份内容',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textMain),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _textCtrl,
            enabled: !busy,
            maxLines: 5,
            minLines: 3,
            // 手机端在两台设备间传文件较麻烦，直接粘贴 JSON 更快
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '备份 JSON 内容',
              hintText: '{ "format": "EasyPassword-plain", ... }',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy || !hasText
                      ? null
                      : () => _import(PlainImportMode.merge, fromText: true),
                  icon: _importing
                      ? _spinner(Colors.white)
                      : const Icon(Icons.merge_outlined, size: 18),
                  label: const Text('增量导入'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy || !hasText
                      ? null
                      : () => _import(PlainImportMode.replace, fromText: true),
                  style:
                      FilledButton.styleFrom(backgroundColor: AppColors.danger),
                  icon: const Icon(Icons.published_with_changes, size: 18),
                  label: const Text('覆盖导入'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: AppColors.textMain,
      ),
    );
  }
}
