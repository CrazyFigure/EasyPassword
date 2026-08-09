/// AI 接入点编辑：协议格式、服务地址、凭据与模型清单。
///
/// 「测试连接」与「保存」都用同一份表单值构造临时 AiProvider，
/// 因此测试通过意味着当前填写的这套配置确实可用，而不是上次保存的那套。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/ai_config.dart';
import '../../services/ai_http_client.dart';
import '../../services/ai_import_service.dart';
import '../../services/data_service.dart';
import '../../state/app_state.dart';
import '../center_dialog.dart';
import '../common/app_menu.dart';
import '../common/app_toast.dart';
import '../common/confirm_dialog.dart';
import '../common/masked_text_controller.dart';
import '../common/secret_text_field.dart';

class AiProviderEditPage extends StatefulWidget {
  /// null 表示新建
  final AiProvider? provider;

  const AiProviderEditPage({super.key, this.provider});

  @override
  State<AiProviderEditPage> createState() => _AiProviderEditPageState();
}

class _AiProviderEditPageState extends State<AiProviderEditPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _baseUrlCtrl;
  late final MaskedTextEditingController _keyCtrl;
  late final TextEditingController _headersCtrl;

  late AiProviderProtocol _protocol;
  late List<AiModel> _models;

  /// 当前进行中的操作：test | save
  String? _busy;

  bool get _isNew => widget.provider == null;

  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    _protocol = provider?.protocol ?? AiProviderProtocol.anthropic;
    _models = List<AiModel>.from(provider?.models ?? const <AiModel>[]);
    _nameCtrl = TextEditingController(text: provider?.name ?? '');
    _baseUrlCtrl = TextEditingController(
      text: provider?.baseUrl ?? _protocol.defaultBaseUrl,
    );
    _keyCtrl = MaskedTextEditingController(text: provider?.apiKey ?? '');
    _headersCtrl = TextEditingController(
      text: (provider?.extraHeaders ?? const <String>[]).join('\n'),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _keyCtrl.dispose();
    _headersCtrl.dispose();
    super.dispose();
  }

  /// 切换协议时，若地址仍是某个协议的默认值就替换为新协议默认值；
  /// 用户手填过的地址一律保留，避免覆盖中转网关地址。
  void _onProtocolChanged(AiProviderProtocol next) {
    final current = _baseUrlCtrl.text.trim();
    final isDefault = current.isEmpty ||
        AiProviderProtocol.values.any((p) => p.defaultBaseUrl == current);
    setState(() {
      _protocol = next;
      if (isDefault) _baseUrlCtrl.text = next.defaultBaseUrl;
    });
  }

  /// 用当前表单值构造接入点。校验失败返回 null 并提示。
  AiProvider? _buildFromForm({required bool requireModels}) {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast('请填写接入点名称');
      return null;
    }
    final baseUrl = _baseUrlCtrl.text.trim();
    if (baseUrl.isEmpty) {
      _toast('请填写接口地址');
      return null;
    }
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      _toast('接口地址需以 http:// 或 https:// 开头');
      return null;
    }
    final apiKey = _keyCtrl.text.trim();
    if (apiKey.isEmpty) {
      _toast('请填写 API Key');
      return null;
    }
    if (requireModels && _models.isEmpty) {
      _toast('请至少添加一个模型');
      return null;
    }
    return AiProvider(
      id: widget.provider?.id ?? DataService.genId(),
      name: name,
      protocol: _protocol,
      baseUrl: baseUrl,
      apiKey: apiKey,
      models: _models,
      extraHeaders: [
        for (final line in _headersCtrl.text.split('\n'))
          if (line.trim().isNotEmpty) line.trim(),
      ],
    );
  }

  /// 测试连接：用第一个模型发一条最小请求。
  Future<void> _testConnection() async {
    final provider = _buildFromForm(requireModels: true);
    if (provider == null) return;
    setState(() => _busy = 'test');
    try {
      await AiImportService().testConnection(provider, provider.models.first);
      if (!mounted) return;
      _toast('连接成功，模型 ${provider.models.first.label} 可用');
    } on AiHttpException catch (error) {
      if (!mounted) return;
      _toast('连接失败：${error.message}');
    } catch (error) {
      if (!mounted) return;
      _toast('连接失败：$error');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _save() async {
    final provider = _buildFromForm(requireModels: true);
    if (provider == null) return;
    setState(() => _busy = 'save');
    try {
      await context.read<AppState>().aiConfig.upsertProvider(provider);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = null);
      _toast('保存失败：$error');
    }
  }

  Future<void> _editModel([int? index]) async {
    final result = await showCenterDialog<AiModel>(
      context: context,
      builder: (_) => _ModelEditSheet(
        model: index == null ? null : _models[index],
      ),
    );
    if (result == null) return;
    setState(() {
      if (index == null) {
        _models.add(result);
      } else {
        _models[index] = result;
      }
    });
  }

  Future<void> _deleteModel(int index) async {
    final model = _models[index];
    final confirmed = await showConfirmDialog(
      context: context,
      title: '删除模型',
      content: '将从该接入点移除「${model.label}」，确定吗？',
      confirmText: '删除',
      isDangerous: true,
    );
    if (confirmed != true) return;
    setState(() => _models.removeAt(index));
  }

  void _toast(String message) {
    if (!mounted) return;
    showAppToast(context, message, kind: toastKindOf(message));
  }

  Widget _spinner(Color color) => SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );

  @override
  Widget build(BuildContext context) {
    final busy = _busy != null;
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? '添加接入点' : '编辑接入点')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildConnectionCard(busy),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('模型',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMain)),
                      ),
                      TextButton.icon(
                        onPressed: busy ? null : () => _editModel(),
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('添加模型'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _buildModelsCard(busy),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(bool busy) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameCtrl,
            enabled: !busy,
            decoration: const InputDecoration(
              labelText: '接入点名称',
              hintText: '例如 Claude 官方 / 公司中转',
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text('协议格式',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain)),
              const Spacer(),
              AppMenuPicker<AiProviderProtocol>(
                value: _protocol,
                enabled: !busy,
                menuWidth: 230,
                onChanged: _onProtocolChanged,
                items: [
                  for (final protocol in AiProviderProtocol.values)
                    AppMenuItem(value: protocol, label: protocol.label),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _baseUrlCtrl,
            enabled: !busy,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: '接口地址',
              hintText: _protocol.defaultBaseUrl,
              helperText: '只填到域名，路径由所选协议自动补全',
            ),
          ),
          const SizedBox(height: 14),
          SecretTextField(
            controller: _keyCtrl,
            enabled: !busy,
            copyLabel: 'API Key',
            decoration: const InputDecoration(labelText: 'API Key'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _headersCtrl,
            enabled: !busy,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: '附加请求头（选填）',
              hintText: 'X-Custom-Header: value',
              helperText: '每行一个，格式 名称: 值；中转网关需要时才填',
              helperMaxLines: 2,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _testConnection,
                  icon: _busy == 'test'
                      ? _spinner(AppColors.primaryDark)
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('测试连接'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : _save,
                  icon: _busy == 'save'
                      ? _spinner(Colors.white)
                      : const Icon(Icons.check, size: 18),
                  label: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModelsCard(bool busy) {
    if (_models.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Text('尚未添加模型，识别页将无法使用该接入点',
              style: TextStyle(fontSize: 13, color: AppColors.textWeak)),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < _models.length; i++) ...[
            if (i > 0)
              const Divider(height: 1, indent: 16, color: AppColors.divider),
            ListTile(
              title: Text(_models[i].label,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain)),
              subtitle: Text(
                _modelSubtitle(_models[i]),
                style: const TextStyle(fontSize: 12, color: AppColors.textWeak),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '编辑',
                    onPressed: busy ? null : () => _editModel(i),
                    icon: const Icon(Icons.edit_outlined,
                        size: 19, color: AppColors.textWeak),
                  ),
                  IconButton(
                    tooltip: '删除',
                    onPressed: busy ? null : () => _deleteModel(i),
                    icon: const Icon(Icons.delete_outline,
                        size: 19, color: AppColors.textWeak),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _modelSubtitle(AiModel model) {
    final parts = <String>[];
    if (model.displayName.trim().isNotEmpty) parts.add(model.id);
    if (model.contextWindow > 0) parts.add('${model.contextWindow} tokens');
    parts.add(model.supportsVision ? '支持图片' : '仅文本');
    return parts.join(' · ');
  }
}

/// 模型新增/编辑弹窗，确定时返回构造好的 AiModel。
class _ModelEditSheet extends StatefulWidget {
  final AiModel? model;

  const _ModelEditSheet({this.model});

  @override
  State<_ModelEditSheet> createState() => _ModelEditSheetState();
}

class _ModelEditSheetState extends State<_ModelEditSheet> {
  late final TextEditingController _idCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _windowCtrl;
  late bool _supportsVision;

  @override
  void initState() {
    super.initState();
    final model = widget.model;
    _idCtrl = TextEditingController(text: model?.id ?? '');
    _nameCtrl = TextEditingController(text: model?.displayName ?? '');
    _windowCtrl = TextEditingController(
      text: (model?.contextWindow ?? 0) > 0 ? '${model!.contextWindow}' : '',
    );
    _supportsVision = model?.supportsVision ?? false;
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _nameCtrl.dispose();
    _windowCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final id = _idCtrl.text.trim();
    if (id.isEmpty) {
      showAppToast(context, '请填写模型 ID', kind: ToastKind.error);
      return;
    }
    final windowText = _windowCtrl.text.trim();
    var window = 0;
    if (windowText.isNotEmpty) {
      final parsed = int.tryParse(windowText);
      if (parsed == null || parsed <= 0) {
        showAppToast(context, '上下文窗口需填写正整数', kind: ToastKind.error);
        return;
      }
      window = parsed;
    }
    Navigator.pop(
      context,
      AiModel(
        id: id,
        displayName: _nameCtrl.text.trim(),
        contextWindow: window,
        supportsVision: _supportsVision,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.model == null ? '添加模型' : '编辑模型',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain)),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: AppColors.textWeak),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _idCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '模型 ID',
              hintText: '请求里实际使用的模型标识',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: '显示名称（选填）',
              helperText: '留空时列表直接显示模型 ID',
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _windowCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: '上下文窗口（选填）',
              hintText: '例如 200000',
              helperText: '仅用于界面提示，不影响请求',
            ),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('支持图片识别',
                style: TextStyle(fontSize: 15, color: AppColors.textMain)),
            subtitle: const Text('关闭后识别页不允许为该模型上传图片',
                style: TextStyle(fontSize: 12, color: AppColors.textWeak)),
            value: _supportsVision,
            activeTrackColor: AppColors.primary,
            onChanged: (value) => setState(() => _supportsVision = value),
          ),
          const SizedBox(height: 10),
          FilledButton(onPressed: _submit, child: const Text('确定')),
        ],
      ),
    );
  }
}
