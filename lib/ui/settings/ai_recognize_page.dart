/// AI 识别导入页：选供应商与模型、上传图片与文本、预览识别结果并增量导入。
///
/// 流程刻意分成「识别」与「导入」两步：AI 存在幻觉与漏识别的可能，
/// 直接写库会污染密码库且只能事后手工清理，因此必须先展示结果与警告，
/// 由用户确认后才调用导入管道。
library;

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../models/ai_config.dart';
import '../../services/ai_http_client.dart';
import '../../services/ai_import_service.dart';
import '../../services/plain_transfer_service.dart';
import '../../state/app_state.dart';
import '../center_dialog.dart';
import '../common/app_menu.dart';
import '../common/app_toast.dart';
import '../common/confirm_dialog.dart';

/// 单张图片上限。base64 编码后体积膨胀约 33%，8MB 原图约合 10.7MB 请求体，
/// 叠加提示词后仍在常见服务的请求上限内。
/// 后续优化项：在这里做一次等比缩放到 1568px 再编码，可显著降低 token 消耗。
const int _kMaxImageBytes = 8 * 1024 * 1024;

/// 全部图片合计上限
const int _kMaxTotalBytes = 15 * 1024 * 1024;

/// 单次识别最多附带的图片数
const int _kMaxImageCount = 9;

class AiRecognizePage extends StatefulWidget {
  /// 作为底部栏 Tab 嵌入时置 false：此时外层 HomePage 已提供 Scaffold，
  /// 再套一层会出现双 AppBar 与重复的安全区内边距。
  final bool standalone;

  const AiRecognizePage({super.key, this.standalone = true});

  @override
  State<AiRecognizePage> createState() => _AiRecognizePageState();
}

class _AiRecognizePageState extends State<AiRecognizePage> {
  late final TextEditingController _textCtrl;

  List<AiProvider> _providers = const [];
  AiProvider? _provider;
  AiModel? _model;
  final List<AiImageInput> _images = [];

  bool _loading = true;

  /// 当前进行中的操作：recognize | import
  String? _busy;

  AiParseResult? _result;
  bool _jsonExpanded = false;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final providers = await context.read<AppState>().aiConfig.getProviders();
    if (!mounted) return;
    setState(() {
      _providers = providers;
      // 只有配了模型的接入点才可用，否则识别时必然失败
      _provider = providers.where((p) => p.models.isNotEmpty).firstOrNull;
      _model = _provider?.models.firstOrNull;
      _loading = false;
    });
  }

  void _onProviderChanged(AiProvider provider) {
    setState(() {
      _provider = provider;
      // 模型属于具体接入点，切换后必须重选，否则会把 A 的模型发给 B
      _model = provider.models.firstOrNull;
      if (!(_model?.supportsVision ?? false)) _images.clear();
    });
  }

  void _onModelChanged(AiModel model) {
    setState(() {
      _model = model;
      // 换到纯文本模型时清掉已选图片，避免用户误以为图片仍会被识别
      if (!model.supportsVision) _images.clear();
    });
  }

  Future<void> _pickImages() async {
    const typeGroup = XTypeGroup(
      label: '图片',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
    );
    final files = await openFiles(acceptedTypeGroups: const [typeGroup]);
    if (files.isEmpty || !mounted) return;

    var totalBytes = _images.fold<int>(0, (sum, img) => sum + img.bytes.length);
    final added = <AiImageInput>[];
    String? rejectReason;

    for (final file in files) {
      if (_images.length + added.length >= _kMaxImageCount) {
        rejectReason = '最多添加 $_kMaxImageCount 张图片';
        break;
      }
      final Uint8List bytes = await file.readAsBytes();
      if (bytes.length > _kMaxImageBytes) {
        rejectReason = '${file.name} 超过 8MB，已跳过';
        continue;
      }
      if (totalBytes + bytes.length > _kMaxTotalBytes) {
        rejectReason = '图片总大小超过 15MB，部分图片未添加';
        break;
      }
      totalBytes += bytes.length;
      added.add(AiImageInput(
        bytes: bytes,
        mediaType: AiImageInput.mediaTypeOf(file.name),
        fileName: file.name,
      ));
    }

    if (!mounted) return;
    setState(() => _images.addAll(added));
    if (rejectReason != null) {
      showAppToast(context, rejectReason, kind: ToastKind.error);
    }
  }

  Future<void> _recognize() async {
    final provider = _provider;
    final model = _model;
    if (provider == null || model == null) {
      showAppToast(context, '请先选择供应商与模型', kind: ToastKind.error);
      return;
    }
    setState(() {
      _busy = 'recognize';
      _result = null;
    });
    final state = context.read<AppState>();
    try {
      final customPrompt = await state.aiConfig.getCustomPrompt();
      final result = await AiImportService().recognize(
        provider: provider,
        model: model,
        text: _textCtrl.text,
        images: model.supportsVision ? _images : const [],
        customPrompt: customPrompt,
      );
      if (!mounted) return;
      setState(() => _result = result);
      showAppToast(context, result.summary, kind: ToastKind.success);
    } on AiHttpException catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message,
          kind: ToastKind.error, duration: const Duration(seconds: 3));
    } on AiImportException catch (error) {
      if (!mounted) return;
      showAppToast(context, error.message,
          kind: ToastKind.error, duration: const Duration(seconds: 3));
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '识别失败：$error',
          kind: ToastKind.error, duration: const Duration(seconds: 3));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _import() async {
    final result = _result;
    if (result == null) return;
    final confirmed = await showConfirmDialog(
      context: context,
      title: '增量导入',
      content: '${result.summary}。\n'
          '这些内容会新增或更新到当前设备，本机其他数据保持不变，'
          '并会同步到你的其他设备。确定继续吗？',
      confirmText: '继续导入',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = 'import');
    final state = context.read<AppState>();
    try {
      final imported = await state.importPlainText(
        result.toImportJson(),
        mode: PlainImportMode.merge,
      );
      if (!mounted) return;
      setState(() => _result = null);
      showAppToast(context, '导入完成，${imported.summary}',
          kind: ToastKind.success, duration: const Duration(seconds: 3));
    } on PlainImportException catch (error) {
      if (!mounted) return;
      showAppToast(context, '导入失败：${error.message}',
          kind: ToastKind.error, duration: const Duration(seconds: 3));
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, '导入失败：$error',
          kind: ToastKind.error, duration: const Duration(seconds: 3));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _editPrompt() async {
    final state = context.read<AppState>();
    final current = await state.aiConfig.getCustomPrompt();
    if (!mounted) return;
    final result = await showCenterDialog<String>(
      context: context,
      builder: (_) => _PromptEditSheet(initial: current),
    );
    if (result == null || !mounted) return;
    await state.aiConfig.setCustomPrompt(result);
    if (!mounted) return;
    showAppToast(context, '提示词已保存', kind: ToastKind.success);
  }

  Widget _spinner(Color color) => SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      const indicator = Center(child: CircularProgressIndicator());
      return widget.standalone
          ? const Scaffold(body: indicator)
          : const ColoredBox(color: AppColors.background, child: indicator);
    }

    final usable = _providers.where((p) => p.models.isNotEmpty).toList();
    final busy = _busy != null;
    final supportsVision = _model?.supportsVision ?? false;
    final hasInput = _textCtrl.text.trim().isNotEmpty || _images.isNotEmpty;

    return Scaffold(
      // 嵌入模式下由 HomePage 的 Scaffold 承担背景与安全区，
      // 这里只保留一个透明壳供 Overlay 定位提示。
      backgroundColor:
          widget.standalone ? AppColors.background : Colors.transparent,
      appBar: widget.standalone
          ? AppBar(
              title: const Text('AI 识别导入'),
              actions: [
                IconButton(
                  tooltip: '提示词设置',
                  onPressed: busy ? null : _editPrompt,
                  icon: const Icon(Icons.tune),
                ),
              ],
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 嵌入底部栏时没有 AppBar，标题与提示词入口在内容区自带一份
                  if (!widget.standalone) ...[
                    Row(
                      children: [
                        const Expanded(
                          child: Text('AI 识别导入',
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textMain)),
                        ),
                        IconButton(
                          tooltip: '提示词设置',
                          onPressed: busy ? null : _editPrompt,
                          icon: const Icon(Icons.tune,
                              color: AppColors.textWeak),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  _buildWarning(),
                  const SizedBox(height: 20),
                  if (usable.isEmpty)
                    _buildNoProvider()
                  else ...[
                    _buildInputCard(usable, busy, supportsVision),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: busy || !hasInput ? null : _recognize,
                      icon: _busy == 'recognize'
                          ? _spinner(Colors.white)
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('开始识别'),
                    ),
                    if (_result != null) ...[
                      const SizedBox(height: 22),
                      _buildResultCard(busy),
                    ],
                  ],
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
              '图片与文字会发送到你选择的 AI 服务进行识别，服务方可能留存这些内容。'
              '请勿上传含真实密码的截图；如必须识别，请先遮盖关键字段。'
              '识别结果只在本机展示，确认导入后才会写入密码库。',
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: AppColors.textMain),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoProvider() {
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
          Text('尚未配置可用的 AI 接入点',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain)),
          SizedBox(height: 6),
          Text('请到 设置 → AI 接入点配置 添加接入点并至少配置一个模型',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textWeak)),
        ],
      ),
    );
  }

  Widget _buildInputCard(
      List<AiProvider> usable, bool busy, bool supportsVision) {
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
          Row(
            children: [
              const Text('供应商',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain)),
              const Spacer(),
              AppMenuPicker<AiProvider>(
                value: _provider ?? usable.first,
                enabled: !busy,
                menuWidth: 230,
                onChanged: _onProviderChanged,
                items: [
                  for (final provider in usable)
                    AppMenuItem(
                      value: provider,
                      label: provider.label,
                      subtitle: provider.protocol.label,
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('模型',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMain)),
              const Spacer(),
              if (_model != null)
                AppMenuPicker<AiModel>(
                  value: _model!,
                  enabled: !busy,
                  menuWidth: 230,
                  onChanged: _onModelChanged,
                  items: [
                    for (final model in _provider?.models ?? const <AiModel>[])
                      AppMenuItem(
                        value: model,
                        label: model.label,
                        subtitle: model.supportsVision ? '支持图片' : '仅文本',
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 16),
          _buildImageSection(busy, supportsVision),
          const SizedBox(height: 16),
          TextField(
            controller: _textCtrl,
            enabled: !busy,
            minLines: 3,
            maxLines: 6,
            // 输入内容决定「开始识别」是否可用，需要随输入刷新
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '文字内容',
              hintText: '粘贴含账号密码的文字，或补充说明图片里要提取什么',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSection(bool busy, bool supportsVision) {
    if (!supportsVision) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.image_not_supported_outlined,
                size: 18, color: AppColors.textFaint),
            SizedBox(width: 8),
            Expanded(
              child: Text('当前模型不支持图片识别，请改用文字输入或切换到支持图片的模型',
                  style: TextStyle(fontSize: 12, color: AppColors.textWeak)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('图片',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain)),
            const SizedBox(width: 8),
            Text('${_images.length}/$_kMaxImageCount',
                style: const TextStyle(fontSize: 12, color: AppColors.textWeak)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < _images.length; i++)
              _ImageThumb(
                image: _images[i],
                onRemove:
                    busy ? null : () => setState(() => _images.removeAt(i)),
              ),
            if (_images.length < _kMaxImageCount)
              _AddImageButton(onTap: busy ? null : _pickImages),
          ],
        ),
      ],
    );
  }

  Widget _buildResultCard(bool busy) {
    final result = _result!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  size: 20, color: AppColors.success),
              const SizedBox(width: 8),
              Expanded(
                child: Text(result.summary,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain)),
              ),
            ],
          ),
          if (result.warnings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF0D48A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: Color(0xFFB07D00)),
                      SizedBox(width: 6),
                      Text('识别提示',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMain)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final warning in result.warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text('· $warning',
                          style: const TextStyle(
                              fontSize: 12,
                              height: 1.45,
                              color: AppColors.textSecondary)),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          InkWell(
            onTap: () => setState(() => _jsonExpanded = !_jsonExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    _jsonExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.textWeak,
                  ),
                  const SizedBox(width: 4),
                  Text(_jsonExpanded ? '收起识别结果' : '展开查看识别结果',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
          if (_jsonExpanded) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: SelectableText(
                result.toPrettyJson(),
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  fontFamily: 'monospace',
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : _import,
            icon: _busy == 'import'
                ? _spinner(Colors.white)
                : const Icon(Icons.merge_outlined, size: 18),
            label: const Text('增量导入'),
          ),
        ],
      ),
    );
  }
}

/// 已选图片缩略图，右上角带删除角标
class _ImageThumb extends StatelessWidget {
  final AiImageInput image;
  final VoidCallback? onRemove;

  const _ImageThumb({required this.image, this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                image.bytes,
                fit: BoxFit.cover,
                // 解码失败时给出占位，避免整页崩溃
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.background,
                  alignment: Alignment.center,
                  child: const Icon(Icons.broken_image_outlined,
                      size: 20, color: AppColors.textFaint),
                ),
              ),
            ),
          ),
          Positioned(
            right: 2,
            top: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 13, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddImageButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _AddImageButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: const SizedBox(
          width: 84,
          height: 84,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_outlined,
                  size: 22, color: AppColors.textWeak),
              SizedBox(height: 4),
              Text('添加图片',
                  style: TextStyle(fontSize: 11, color: AppColors.textWeak)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 自定义提示词编辑弹窗
class _PromptEditSheet extends StatefulWidget {
  final String initial;

  const _PromptEditSheet({required this.initial});

  @override
  State<_PromptEditSheet> createState() => _PromptEditSheetState();
}

class _PromptEditSheetState extends State<_PromptEditSheet> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
              const Expanded(
                child: Text('自定义提示词',
                    style: TextStyle(
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
          const SizedBox(height: 8),
          const Text(
            '这段文字会追加到内置提示词之后，用来表达你的个性化要求。'
            '内置的结构说明与输出格式约束不受影响，留空即可恢复默认行为。',
            style: TextStyle(
                fontSize: 12, height: 1.5, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _ctrl,
            autofocus: true,
            minLines: 4,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: '例如：忽略没有密码的条目；把所有条目放进「导入」文件夹',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context, _ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }
}
