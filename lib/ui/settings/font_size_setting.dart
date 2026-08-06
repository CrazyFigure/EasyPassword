/// 字体设置页：字号即时预览、系统字体选择、保存或取消回退。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../services/font_catalog_service.dart';
import '../../services/settings_service.dart';
import '../../state/app_state.dart';
import '../center_dialog.dart';

class FontSizeSettingPage extends StatefulWidget {
  const FontSizeSettingPage({super.key});

  @override
  State<FontSizeSettingPage> createState() => _FontSizeSettingPageState();
}

class _FontSizeSettingPageState extends State<FontSizeSettingPage> {
  FontSizeMode _sizeMode = FontSizeMode.system;
  String? _fontFamily;
  FontSizeMode _originalSizeMode = FontSizeMode.system;
  String? _originalFontFamily;
  AppState? _appState;
  bool _loaded = false;
  bool _saved = false;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  /// 从持久化设置加载原值；原值单独保留，用于取消或系统返回时回退预览。
  Future<void> _load() async {
    final state = context.read<AppState>();
    final sizeMode = await state.settings.getFontSizeMode();
    final family = await state.settings.getFontFamily();
    if (!mounted) return;
    setState(() {
      _appState = state;
      _sizeMode = sizeMode;
      _fontFamily = family;
      _originalSizeMode = sizeMode;
      _originalFontFamily = family;
      _loaded = true;
    });
  }

  /// 选择变化后只更新内存主题，使全页立即预览；此时不写数据库。
  void _preview(
      {FontSizeMode? sizeMode, String? family, bool setFamily = false}) {
    setState(() {
      if (sizeMode != null) _sizeMode = sizeMode;
      if (setFamily) _fontFamily = family;
    });
    _appState?.previewTypography(_sizeMode, _fontFamily);
  }

  /// 保存后正式生效；只有保存成功才允许页面退出时跳过回退。
  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await _appState?.saveTypography(_sizeMode, _fontFamily);
    if (!mounted) return;
    _saved = true;
    Navigator.pop(context);
  }

  void _cancel() {
    _restorePreview();
    Navigator.pop(context);
  }

  void _restorePreview() {
    if (_saved) return;
    _appState?.previewTypography(_originalSizeMode, _originalFontFamily);
  }

  /// 字体目录直到点击选择框才查询；空字符串作为“系统默认”的明确返回值。
  Future<void> _openFontPicker() async {
    final choice = await showCenterDialog<String>(
      context: context,
      maxWidth: 460,
      builder: (_) => _FontPickerDialog(initialFamily: _fontFamily),
    );
    if (choice == null || !mounted) return;
    _preview(family: choice.isEmpty ? null : choice, setFamily: true);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _restorePreview();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('字体')),
        body: !_loaded
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const _SectionTitle('字体大小'),
                  const SizedBox(height: 10),
                  _buildSizeOptions(),
                  const SizedBox(height: 20),
                  _buildPreview(),
                  const SizedBox(height: 24),
                  const _SectionTitle('字体'),
                  const SizedBox(height: 10),
                  _buildFontPicker(),
                  const SizedBox(height: 8),
                  Text(
                    '仅显示当前${Platform.isWindows ? ' Windows' : Platform.isAndroid ? ' Android' : ''}设备已安装的字体，列表在展开时加载。',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textWeak,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : _cancel,
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSizeOptions() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: RadioGroup<FontSizeMode>(
        groupValue: _sizeMode,
        onChanged: (value) {
          if (value != null) _preview(sizeMode: value);
        },
        child: Column(
          children: [
            for (var index = 0;
                index < FontSizeMode.values.length;
                index++) ...[
              RadioListTile<FontSizeMode>(
                title: Text(FontSizeMode.values[index].label),
                value: FontSizeMode.values[index],
                activeColor: AppColors.primary,
              ),
              if (index != FontSizeMode.values.length - 1)
                const Divider(
                  height: 1,
                  indent: 56,
                  color: AppColors.divider,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('预览', style: TextStyle(fontSize: 12, color: AppColors.textWeak)),
          SizedBox(height: 8),
          Text(
            'Google · 密码 · user@gmail.com',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textMain,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '示例文字 Sample text 123',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildFontPicker() {
    final label = _fontFamily ?? '系统默认';
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _openFontPicker,
        hoverColor: AppColors.primary.withValues(alpha: 0.06),
        splashColor: AppColors.primary.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              const Icon(Icons.font_download_outlined,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontFamily: _fontFamily,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.keyboard_arrow_down, color: AppColors.textWeak),
            ],
          ),
        ),
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

/// 可搜索字体弹窗：先展示加载态，平台返回后原地更新，不阻塞设置页首屏。
class _FontPickerDialog extends StatefulWidget {
  final String? initialFamily;
  const _FontPickerDialog({this.initialFamily});

  @override
  State<_FontPickerDialog> createState() => _FontPickerDialogState();
}

class _FontPickerDialogState extends State<_FontPickerDialog> {
  final FontCatalogService _catalog = FontCatalogService();
  final TextEditingController _searchController = TextEditingController();
  List<String> _families = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 弹窗已展开后才执行平台查询，满足字体目录按需加载约束。
  Future<void> _load() async {
    final families = await _catalog.listInstalledFamilies();
    if (!mounted) return;
    setState(() {
      _families = families;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final visibleFamilies = query.isEmpty
        ? _families
        : _families
            .where((family) => family.toLowerCase().contains(query))
            .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '选择字体',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: AppColors.textWeak),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: '搜索已安装字体',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 340,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      _FontOptionTile(
                        label: '系统默认',
                        selected: widget.initialFamily == null,
                        onTap: () => Navigator.pop(context, ''),
                      ),
                      if (visibleFamilies.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 36),
                          child: Text(
                            query.isEmpty
                                ? '未读取到字体列表，仍可使用系统默认字体'
                                : '没有匹配“${_searchController.text.trim()}”的字体',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textWeak,
                            ),
                          ),
                        )
                      else
                        for (final family in visibleFamilies)
                          _FontOptionTile(
                            label: family,
                            fontFamily: family,
                            selected: widget.initialFamily == family,
                            onTap: () => Navigator.pop(context, family),
                          ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _FontOptionTile extends StatelessWidget {
  final String label;
  final String? fontFamily;
  final bool selected;
  final VoidCallback onTap;

  const _FontOptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      selected: selected,
      selectedTileColor: AppColors.primaryLight,
      title: Text(
        label,
        style: TextStyle(fontFamily: fontFamily, color: AppColors.textMain),
      ),
      trailing: selected
          ? const Icon(Icons.check, size: 20, color: AppColors.primaryDark)
          : null,
      onTap: onTap,
    );
  }
}
