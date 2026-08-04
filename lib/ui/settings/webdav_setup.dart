/// WebDAV 同步设置页（需求 3.5.3 / 4）
/// 三个独立操作：测试连接 → 保存配置 → 立即同步
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../state/app_state.dart';

class WebDavSetupPage extends StatefulWidget {
  const WebDavSetupPage({super.key});

  @override
  State<WebDavSetupPage> createState() => _WebDavSetupPageState();
}

class _WebDavSetupPageState extends State<WebDavSetupPage> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;
  String? _busy; // 进行中的操作：test | save | sync
  String? _status;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();
    _userCtrl = TextEditingController();
    _passCtrl = TextEditingController();
    // 监听地址变化：输入坚果云根路径时实时给出友好提示（避免同步时才报错）
    _urlCtrl.addListener(_onUrlChanged);
    _load();
  }

  /// 地址变化时刷新界面，触发坚果云路径提示的显示/隐藏
  void _onUrlChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// 判断是否为坚果云根目录（/dav 或 /dav/，其后无子目录）
  /// 坚果云不允许直接写入根目录，需在网页端先建子文件夹
  bool _isJianguoyunRootPath(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return false;
    if (uri.host.toLowerCase() != 'dav.jianguoyun.com') return false;
    // 路径段去掉空段后：['dav'] 视为根；含子目录则不再提示
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return segs.length <= 1;
  }

  /// 一键填入建议的子目录路径（需用户在网页端先创建同名文件夹）
  void _fillSuggestedPath() {
    _urlCtrl.text = 'https://dav.jianguoyun.com/dav/EasyPassword/';
    // 光标移到末尾，便于继续编辑
    _urlCtrl.selection =
        TextSelection.collapsed(offset: _urlCtrl.text.length);
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final cfg = await state.settings.getWebDavConfig();
    if (cfg != null && mounted) {
      _urlCtrl.text = cfg.url;
      _userCtrl.text = cfg.user;
      _passCtrl.text = cfg.pass;
    }
  }

  @override
  void dispose() {
    _urlCtrl.removeListener(_onUrlChanged);
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  /// 测试连接：用当前表单值探测服务器（不保存）
  Future<void> _testConnection() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _setStatus('请填写 WebDAV 服务器地址');
      return;
    }
    setState(() => _busy = 'test');
    try {
      await context.read<AppState>().webdav.testConnection(
          url, _userCtrl.text.trim(), _passCtrl.text);
      _setStatus('连接成功，WebDAV 服务可用');
    } catch (e) {
      _setStatus(_fmtError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// 保存配置：仅写入本地设置（不同步）
  Future<void> _saveConfig() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _setStatus('请填写 WebDAV 服务器地址');
      return;
    }
    setState(() => _busy = 'save');
    try {
      await context.read<AppState>().settings
          .setWebDavConfig(url, _userCtrl.text.trim(), _passCtrl.text);
      _setStatus('配置已保存');
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// 立即同步：使用已保存的配置执行拉取合并推送
  Future<void> _syncNow() async {
    final state = context.read<AppState>();
    final cfg = await state.settings.getWebDavConfig();
    if (cfg == null) {
      _setStatus('尚未保存配置，请先点击「保存配置」');
      return;
    }
    setState(() => _busy = 'sync');
    await state.syncNow();
    if (!mounted) return;
    setState(() {
      _busy = null;
      _status = state.syncMessage;
    });
  }

  void _setStatus(String msg) {
    if (!mounted) return;
    setState(() => _status = msg);
  }

  String _fmtError(Object e) => e.toString().replaceFirst('Exception: ', '');

  /// 坚果云根路径友好提示卡：在输入阶段提前告知，避免同步时才报 403
  Widget _buildJianguoyunHint() {
    // 温和的警示底色（浅黄），区别于错误红与成功绿
    const bg = Color(0xFFFFF8E1);
    const border = Color(0xFFFFE082);
    const iconColor = Color(0xFFF59E0B);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: iconColor),
              SizedBox(width: 6),
              Text(
                '坚果云路径提示',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '坚果云不允许直接写入根目录 /dav/，需先在网页端（www.jianguoyun.com）'
            '新建一个子文件夹，并把地址改为该子文件夹的路径，否则同步会失败。',
            style: TextStyle(fontSize: 12, height: 1.5, color: AppColors.textMain),
          ),
          const SizedBox(height: 8),
          // 一键填入建议路径
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _fillSuggestedPath,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primaryDark,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.auto_fix_high, size: 15),
              label: const Text('填入建议路径',
                  style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
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
      appBar: AppBar(title: const Text('WebDAV 同步')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryLightBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '支持坚果云等标准 WebDAV 服务。数据以加密快照存储，本地与远端均不保存明文。',
              style: TextStyle(fontSize: 13, color: AppColors.textMain),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '服务器地址',
              hintText: 'https://dav.example.com/easypassword/',
            ),
          ),
          // 输入坚果云根路径时，输入阶段即友好提醒（无需等到同步报错）
          if (_isJianguoyunRootPath(_urlCtrl.text)) _buildJianguoyunHint(),
          const SizedBox(height: 12),
          TextField(
            controller: _userCtrl,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passCtrl,
            obscureText: true,
            decoration: const InputDecoration(labelText: '密码（应用密码）'),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : _testConnection,
                  child: _busy == 'test'
                      ? _spinner(AppColors.primaryDark)
                      : const Text('测试连接'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : _saveConfig,
                  child: _busy == 'save'
                      ? _spinner(AppColors.primaryDark)
                      : const Text('保存配置'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : _syncNow,
                  child: _busy == 'sync'
                      ? _spinner(Colors.white)
                      : const Text('立即同步'),
                ),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 16),
            Center(
              child: Text(_status!,
                  style: TextStyle(
                      fontSize: 13,
                      color: _status!.contains('失败')
                          ? AppColors.danger
                          : AppColors.success)),
            ),
          ],
        ],
      ),
    );
  }
}
