/// WebDAV 多端同步设置页：连接配置、三种同步方向与自动同步策略。
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../services/webdav_service.dart';
import '../../state/app_state.dart';
import '../common/app_menu.dart';
import '../common/app_toast.dart';
import '../common/confirm_dialog.dart';
import '../common/masked_text_controller.dart';
import '../common/secret_text_field.dart';

class WebDavSetupPage extends StatefulWidget {
  const WebDavSetupPage({super.key});

  @override
  State<WebDavSetupPage> createState() => _WebDavSetupPageState();
}

class _WebDavSetupPageState extends State<WebDavSetupPage> {
  late final TextEditingController _urlCtrl;
  late final TextEditingController _userCtrl;
  late final MaskedTextEditingController _passCtrl;
  late final TextEditingController _pathCtrl;
  String? _busy; // 当前操作：test | save | local | remote | automatic

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController();
    _userCtrl = TextEditingController();
    _passCtrl = MaskedTextEditingController();
    _pathCtrl = TextEditingController(text: WebDavDefaults.remotePath);
    _load();
  }

  Future<void> _load() async {
    final state = context.read<AppState>();
    final config = await state.settings.getWebDavConfig();
    if (config != null && mounted) {
      setState(() {
        _urlCtrl.text = config.url;
        _userCtrl.text = config.user;
        _passCtrl.text = config.pass;
        _pathCtrl.text = config.path;
      });
    }
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  /// 总开关负责整组 WebDAV 能力；重新开启时 AppState 只调度安全的双向合并。
  Future<void> _toggleWebDav(bool enabled) async {
    await context.read<AppState>().updateWebDavEnabled(enabled);
    if (!mounted) return;
    _setStatus(context.read<AppState>().syncMessage ??
        (enabled ? 'WebDAV 已启用' : 'WebDAV 已关闭'));
  }

  /// 测试连接也会验证写权限并自动创建配置的远端路径，但不保存表单。
  Future<void> _testConnection() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _setStatus('请填写 WebDAV 根地址');
      return;
    }
    setState(() => _busy = 'test');
    try {
      await context.read<AppState>().webdav.testConnection(
            url,
            _userCtrl.text.trim(),
            _passCtrl.text,
            remotePath: _pathCtrl.text,
          );
      final path = WebDavService.normalizeRemotePath(_pathCtrl.text);
      _setStatus('连接成功，$path 已就绪');
    } catch (error) {
      _setStatus(_formatError(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// 保存前完成连接与目录创建，避免出现“配置保存了但首次同步才发现不可写”。
  Future<void> _saveConfig() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      _setStatus('请填写 WebDAV 根地址');
      return;
    }
    setState(() => _busy = 'save');
    final state = context.read<AppState>();
    try {
      await state.saveWebDavConfig(
        url,
        _userCtrl.text.trim(),
        _passCtrl.text,
        _pathCtrl.text,
      );
      _pathCtrl.text = WebDavService.normalizeRemotePath(_pathCtrl.text);
      _setStatus('配置已保存${state.autoSyncEnabled ? '，双向自动同步已开始运行' : ''}');
    } catch (error) {
      _setStatus(_formatError(error));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  /// 执行同步操作；两个覆盖方向会先明确告知被替换的一端。
  Future<void> _runSync(WebDavSyncMode mode) async {
    final state = context.read<AppState>();
    if (!state.webDavEnabled) {
      _setStatus('请先打开 WebDAV 总开关');
      return;
    }
    if (await state.settings.getWebDavConfig() == null) {
      _setStatus('尚未保存配置，请先点击“保存配置”');
      return;
    }
    if (!mounted) return;
    if (mode != WebDavSyncMode.automatic) {
      final localToRemote = mode == WebDavSyncMode.localToRemote;
      final confirmed = await showConfirmDialog(
        context: context,
        title: localToRemote ? '本地覆盖远端' : '远端覆盖本地',
        content: localToRemote
            ? '远端快照将被当前设备的数据完整替换。确定继续吗？'
            : '当前设备的密码、API Key 和同步设置将被远端快照完整替换。确定继续吗？',
        confirmText: '继续覆盖',
        isDangerous: true,
      );
      if (confirmed != true || !mounted) return;
    }

    final operation = switch (mode) {
      WebDavSyncMode.localToRemote => 'local',
      WebDavSyncMode.remoteToLocal => 'remote',
      WebDavSyncMode.automatic => 'automatic',
    };
    setState(() => _busy = operation);
    await state.syncNow(mode: mode);
    if (!mounted) return;
    setState(() {
      _busy = null;
    });
    final msg = state.syncMessage;
    if (msg != null) {
      showAppToast(context, msg, kind: toastKindOf(msg));
    }
  }

  void _setStatus(String message) {
    if (!mounted) return;
    showAppToast(context, message, kind: toastKindOf(message));
  }

  String _formatError(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  Widget _spinner(Color color) => SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final busy = _busy != null || state.syncing;
    final enabled = state.webDavEnabled;
    return Scaffold(
      appBar: AppBar(title: const Text('WebDAV 同步')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFeatureToggle(state, busy),
                  const SizedBox(height: 14),
                  _buildIntro(),
                  const SizedBox(height: 20),
                  _buildConnectionCard(busy, enabled),
                  const SizedBox(height: 22),
                  const _SectionTitle('同步方向'),
                  const SizedBox(height: 10),
                  _buildSyncActions(busy, enabled),
                  const SizedBox(height: 22),
                  const _SectionTitle('自动同步'),
                  const SizedBox(height: 10),
                  _buildAutomaticSettings(state, busy, enabled),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 总开关独立成卡片，关闭后的说明与禁用态保持在同一视觉焦点内。
  Widget _buildFeatureToggle(AppState state, bool busy) {
    return Container(
      decoration: BoxDecoration(
        color: state.webDavEnabled ? AppColors.primaryLightBg : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: state.webDavEnabled ? AppColors.primary : AppColors.border,
        ),
      ),
      child: SwitchListTile(
        secondary: Icon(
          state.webDavEnabled ? Icons.cloud_done_outlined : Icons.cloud_off,
          color:
              state.webDavEnabled ? AppColors.primaryDark : AppColors.textWeak,
        ),
        title: const Text('启用 WebDAV'),
        subtitle: Text(
          state.webDavEnabled ? '配置、手动同步和双向自动同步均已启用' : '开启后才能修改配置和进行同步',
        ),
        value: state.webDavEnabled,
        activeTrackColor: AppColors.primary,
        onChanged: busy ? null : _toggleWebDav,
      ),
    );
  }

  Widget _buildIntro() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLightBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.enhanced_encryption_outlined,
              size: 20, color: AppColors.primaryDark),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '密码、API Key、应用锁和显示设置会以加密快照同步。远端路径不存在时会自动逐级创建。',
              style: TextStyle(
                  fontSize: 13, height: 1.5, color: AppColors.textMain),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(bool busy, bool featureEnabled) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          TextField(
            controller: _urlCtrl,
            enabled: featureEnabled && !busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'WebDAV 根地址',
              hintText: 'https://dav.example.com/dav/',
              helperText: '填写 WebDAV 服务提供的根地址',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _userCtrl,
            enabled: featureEnabled && !busy,
            decoration: const InputDecoration(labelText: '用户名'),
          ),
          const SizedBox(height: 12),
          SecretTextField(
            controller: _passCtrl,
            enabled: featureEnabled && !busy,
            copyLabel: 'WebDAV 密码',
            decoration: const InputDecoration(labelText: '密码（应用密码）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pathCtrl,
            enabled: featureEnabled && !busy,
            decoration: const InputDecoration(
              labelText: '远端路径',
              hintText: WebDavDefaults.remotePath,
              helperText: '目录不存在时自动创建，例如 /EasyPassword',
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy || !featureEnabled ? null : _testConnection,
                  icon: _busy == 'test'
                      ? _spinner(AppColors.primaryDark)
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('测试连接'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy || !featureEnabled ? null : _saveConfig,
                  icon: _busy == 'save'
                      ? _spinner(Colors.white)
                      : const Icon(Icons.cloud_done_outlined, size: 18),
                  label: const Text('保存配置'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 三个方向动作在窄屏纵向排列，宽屏并排；每张卡都通过 InkWell 提供
  /// Hover、按压水波纹和禁用反馈。
  Widget _buildSyncActions(bool busy, bool featureEnabled) {
    final actions = [
      _SyncActionCard(
        icon: Icons.cloud_upload_outlined,
        title: '本地覆盖远端',
        subtitle: '强制上传当前设备全部数据',
        busy: _busy == 'local',
        enabled: featureEnabled && !busy,
        onTap: () => _runSync(WebDavSyncMode.localToRemote),
      ),
      _SyncActionCard(
        icon: Icons.cloud_download_outlined,
        title: '远端覆盖本地',
        subtitle: '强制用远端快照替换本机',
        busy: _busy == 'remote',
        enabled: featureEnabled && !busy,
        onTap: () => _runSync(WebDavSyncMode.remoteToLocal),
      ),
      _SyncActionCard(
        icon: Icons.sync,
        title: '自动同步',
        subtitle: '按修改时间合并后双向更新',
        busy: _busy == 'automatic',
        enabled: featureEnabled && !busy,
        emphasized: true,
        onTap: () => _runSync(WebDavSyncMode.automatic),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 680) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: actions[i]),
              ],
            ],
          );
        }
        return Column(
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(height: 10),
              actions[i],
            ],
          ],
        );
      },
    );
  }

  Widget _buildAutomaticSettings(
      AppState state, bool busy, bool featureEnabled) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          SwitchListTile(
            secondary:
                const Icon(Icons.bolt_outlined, color: AppColors.primary),
            title: const Text('修改后自动同步'),
            subtitle: const Text('断网时保留变更，恢复联网后自动重试'),
            value: state.autoSyncEnabled,
            activeTrackColor: AppColors.primary,
            onChanged: busy || !featureEnabled
                ? null
                : (enabled) => state.updateAutoSync(enabled: enabled),
          ),
          const Divider(height: 1, indent: 56, color: AppColors.divider),
          ListTile(
            leading:
                const Icon(Icons.schedule_outlined, color: AppColors.primary),
            title: const Text('定时同步'),
            subtitle: const Text('应用运行期间定期拉取其他设备的修改'),
            // 同步间隔与默认主页共用同一款锚点式下拉，保留禁用态反馈。
            trailing: AppMenuPicker<int>(
              value: state.autoSyncIntervalMinutes,
              enabled: featureEnabled && state.autoSyncEnabled && !busy,
              menuWidth: 150,
              onChanged: (minutes) =>
                  state.updateAutoSync(enabled: true, minutes: minutes),
              items: const [
                AppMenuItem(value: 5, label: '5 分钟'),
                AppMenuItem(value: 15, label: '15 分钟'),
                AppMenuItem(value: 30, label: '30 分钟'),
                AppMenuItem(value: 60, label: '60 分钟'),
              ],
            ),
          ),
          if (state.lastSyncAt != null) ...[
            const Divider(height: 1, indent: 56, color: AppColors.divider),
            ListTile(
              leading: const Icon(Icons.history, color: AppColors.primary),
              title: const Text('最近同步'),
              subtitle: Text(_formatTime(state.lastSyncAt!)),
            ),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
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

class _SyncActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool busy;
  final bool enabled;
  final bool emphasized;
  final VoidCallback onTap;

  const _SyncActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.enabled,
    required this.onTap,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final background = emphasized ? AppColors.primaryLightBg : Colors.white;
    return Material(
      color: enabled ? background : AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: emphasized ? AppColors.primary : AppColors.border,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        hoverColor: AppColors.primary.withValues(alpha: 0.06),
        splashColor: AppColors.primary.withValues(alpha: 0.12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(icon,
                    size: 24,
                    color:
                        enabled ? AppColors.primaryDark : AppColors.textFaint),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color:
                            enabled ? AppColors.textMain : AppColors.textFaint,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.35,
                        color: AppColors.textWeak,
                      ),
                    ),
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
