/// AI 接入点列表：查看、新增、编辑、删除识别服务配置。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/ai_config.dart';
import '../../state/app_state.dart';
import '../common/app_toast.dart';
import '../common/confirm_dialog.dart';
import 'ai_provider_edit_page.dart';

class AiProviderListPage extends StatefulWidget {
  const AiProviderListPage({super.key});

  @override
  State<AiProviderListPage> createState() => _AiProviderListPageState();
}

class _AiProviderListPageState extends State<AiProviderListPage> {
  List<AiProvider> _providers = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final providers = await context.read<AppState>().aiConfig.getProviders();
    if (!mounted) return;
    setState(() {
      _providers = providers;
      _loading = false;
    });
  }

  /// 打开编辑页；返回 true 表示有保存，需要重新读取列表。
  Future<void> _openEditor([AiProvider? provider]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AiProviderEditPage(provider: provider),
      ),
    );
    if (saved == true) await _load();
  }

  Future<void> _delete(AiProvider provider) async {
    final confirmed = await showConfirmDialog(
      context: context,
      title: '删除接入点',
      content: '将删除「${provider.label}」及其下的全部模型配置，确定吗？',
      confirmText: '删除',
      isDangerous: true,
    );
    if (confirmed != true || !mounted) return;
    await context.read<AppState>().aiConfig.deleteProvider(provider.id);
    if (!mounted) return;
    showAppToast(context, '已删除', kind: ToastKind.success);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI 接入点')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                        if (_providers.isEmpty)
                          _buildEmpty()
                        else
                          for (final provider in _providers) ...[
                            _ProviderCard(
                              provider: provider,
                              onTap: () => _openEditor(provider),
                              onDelete: () => _delete(provider),
                            ),
                            const SizedBox(height: 10),
                          ],
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: () => _openEditor(),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('添加接入点'),
                        ),
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
              'API Key 以明文保存在本机，并会随 WebDAV 加密快照同步到你的其他设备。'
              '请只填写你信任的服务地址，并优先使用权限受限的密钥。',
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: AppColors.textMain),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.smart_toy_outlined, size: 36, color: AppColors.textFaint),
          SizedBox(height: 12),
          Text('尚未配置 AI 接入点',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain)),
          SizedBox(height: 6),
          Text('添加一个接入点后即可使用 AI 识别导入',
              style: TextStyle(fontSize: 13, color: AppColors.textWeak)),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final AiProvider provider;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProviderCard({
    required this.provider,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // 缺少模型时高亮提示：没有模型的接入点在识别页无法使用
    final hasModels = provider.models.isNotEmpty;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.primary.withValues(alpha: 0.06),
        splashColor: AppColors.primary.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.smart_toy_outlined,
                  size: 24, color: AppColors.primaryDark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.label,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMain),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${provider.protocol.label} · '
                      '${hasModels ? '${provider.models.length} 个模型' : '未配置模型'}',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: hasModels
                            ? AppColors.textWeak
                            : AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '删除',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline,
                    size: 20, color: AppColors.textWeak),
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
