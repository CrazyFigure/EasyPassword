/// 字体大小设置页（需求 3.5.2：默认跟随系统）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../state/app_state.dart';

class FontSizeSettingPage extends StatefulWidget {
  const FontSizeSettingPage({super.key});

  @override
  State<FontSizeSettingPage> createState() => _FontSizeSettingPageState();
}

class _FontSizeSettingPageState extends State<FontSizeSettingPage> {
  double _scale = 1.0;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final scale = await state.settings.getFontScale();
    if (!mounted) return;
    setState(() {
      _scale = scale;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('字体大小')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 选项：跟随系统 / 小 / 标准 / 大 / 特大
          for (final opt in _options) _optionTile(opt),
          const SizedBox(height: 24),
          // 预览
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('预览',
                    style: TextStyle(fontSize: 12, color: AppColors.textWeak)),
                const SizedBox(height: 8),
                Text('Google · 密码 · user@gmail.com',
                    style: TextStyle(
                        fontSize: 15 * _scale,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMain)),
                const SizedBox(height: 4),
                Text('示例文字示例文字',
                    style: TextStyle(
                        fontSize: 13 * _scale, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _optionTile(double scale) {
    final label = scale == 1.0 ? '跟随系统' : _labelFor(scale);
    return RadioListTile<double>(
      title: Text(label),
      value: scale,
      groupValue: _scale,
      activeColor: AppColors.primary,
      onChanged: (v) async {
        if (v == null) return;
        setState(() => _scale = v);
        await context.read<AppState>().updateFontScale(v);
      },
    );
  }

  String _labelFor(double scale) {
    if (scale == 0.85) return '小';
    if (scale == 1.15) return '大';
    if (scale == 1.3) return '特大';
    return '标准';
  }

  static const _options = [1.0, 0.85, 1.0, 1.15, 1.3];
}
