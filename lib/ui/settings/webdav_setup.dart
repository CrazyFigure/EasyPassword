/// WebDAV 同步设置页（需求 3.5.3 / 4）
/// 配置服务器地址、账号密码；测试连接并立即同步
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
  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();
    _userCtrl = TextEditingController();
    _passCtrl = TextEditingController();
    _load();
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
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndSync() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _setStatus('请填写 WebDAV 服务器地址');
      return;
    }
    setState(() => _busy = true);
    final state = context.read<AppState>();
    await state.settings.setWebDavConfig(url, _userCtrl.text.trim(), _passCtrl.text);
    await state.syncNow();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = state.syncMessage;
    });
  }

  void _setStatus(String msg) {
    setState(() => _status = msg);
  }

  @override
  Widget build(BuildContext context) {
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
          FilledButton(
            onPressed: _busy ? null : _saveAndSync,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('保存并立即同步'),
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
