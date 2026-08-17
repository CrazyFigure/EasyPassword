/// 设置页：应用锁 / 字体 / 底部栏自定义 / WebDAV 同步 / 关于
/// （需求 3.5.1 - 3.5.5）
library;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_environment.dart';
import '../../core/constants.dart';
import '../../state/app_state.dart';
import '../center_dialog.dart';
import '../common/confirm_dialog.dart';
import 'ai_provider_list_page.dart';
import 'ai_recognize_page.dart';
import 'app_lock_setup.dart';
import 'font_size_setting.dart';
import 'plain_transfer_page.dart';
import 'tab_customize_sheet.dart';
import 'update_check_dialog.dart';
import 'webdav_setup.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text('设置',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain)),
        ),
        // ===== 安全 =====
        const _SectionLabel('安全'),
        _SettingsCard(children: [
          _ToggleTile(
            icon: Icons.lock_outline,
            title: '应用锁',
            subtitle: '使用密码保护应用',
            value: state.appLockEnabled,
            onChanged: (v) => _toggleAppLock(context, v),
          ),
          const _Divider(),
          _ActionTile(
            icon: Icons.help_outline,
            title: '安全问题',
            subtitle: '恢复应用锁密码',
            onTap: () async {
              await state.appLock.getSecurityQuestion();
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AppLockSetupPage()),
              );
            },
          ),
          if (_isMobilePlatform) ...[
            const _Divider(),
            _ToggleTile(
              icon: Icons.keyboard_outlined,
              title: '使用安全键盘',
              subtitle: state.secureKeyboardEnabled
                  ? '密码输入时优先使用系统安全键盘'
                  : '允许使用其他输入法，密码仍会隐藏',
              value: state.secureKeyboardEnabled,
              onChanged: state.updateSecureKeyboard,
            ),
          ],
        ]),
        const SizedBox(height: 16),
        // ===== 显示 =====
        const _SectionLabel('显示'),
        _SettingsCard(children: [
          _ActionTile(
            icon: Icons.text_fields,
            title: '字体',
            subtitle:
                '${state.fontSizeMode.label} · ${state.fontFamily ?? '系统默认'}',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FontSizeSettingPage()),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        // ===== 导航栏 =====
        const _SectionLabel('导航栏'),
        _SettingsCard(children: [
          _ActionTile(
            icon: Icons.tab_outlined,
            title: '底部栏选项',
            subtitle: '开关 Tab、调整顺序、设置默认主页',
            onTap: () => showCenterDialog<void>(
              context: context,
              builder: (_) => const TabCustomizeSheet(),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        // ===== 数据同步 =====
        const _SectionLabel('数据同步'),
        _SettingsCard(children: [
          _ActionTile(
            icon: Icons.sync_outlined,
            title: 'WebDAV 同步',
            subtitle: state.syncing
                ? '同步中...'
                : (!state.webDavEnabled
                    ? '已关闭'
                    : (state.syncMessage ?? '多端合并、覆盖与定时同步')),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WebDavSetupPage()),
            ),
          ),
          const _Divider(),
          _ActionTile(
            icon: Icons.import_export,
            title: '明文导入导出',
            subtitle: '本地明文备份与恢复，支持增量或覆盖导入',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PlainTransferPage()),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        // ===== AI 助手 =====
        const _SectionLabel('AI 助手'),
        _SettingsCard(children: [
          _ActionTile(
            icon: Icons.smart_toy_outlined,
            title: 'AI 接入点配置',
            subtitle: '管理识别服务的协议、地址与可用模型',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiProviderListPage()),
            ),
          ),
          const _Divider(),
          _ActionTile(
            icon: Icons.document_scanner_outlined,
            title: 'AI 识别导入',
            subtitle: '从图片或文字中提取密码，确认后增量导入',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AiRecognizePage()),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        // ===== 关于 =====
        const _SectionLabel('关于'),
        _SettingsCard(children: [
          _ActionTile(
            icon: Icons.system_update_alt,
            title: '版本与更新',
            // 开发版明确标记独立数据环境，避免测试时误以为正在操作安装版数据。
            subtitle: AppEnvironment.usesDevelopmentStorage
                ? 'EasyPassword v${AppInfo.currentVersion} · 开发环境 · 点击检测更新'
                : 'EasyPassword v${AppInfo.currentVersion} · 点击检测更新',
            onTap: () => showUpdateCheckDialog(context),
          ),
          const _Divider(),
          _ActionTile(
            icon: Icons.link,
            title: 'GitHub',
            subtitle: AppInfo.repoUrl,
            onTap: () => launchUrl(
              Uri.parse(AppInfo.repoUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ]),
        const SizedBox(height: 24),
        const Center(
          child: Text('EasyPassword · 安全管理你的密码',
              style: TextStyle(fontSize: 12, color: AppColors.textFaint)),
        ),
      ],
    );
  }

  /// 安全键盘由 Android/iOS 输入法实现，桌面端不展示无效设置项。
  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _toggleAppLock(BuildContext context, bool enable) async {
    final state = context.read<AppState>();
    if (enable) {
      // 开启：进入设置向导（设置密码 + 安全问题）
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const AppLockSetupPage()),
      );
    } else {
      // 关闭：确认后禁用
      final ok = await showConfirmDialog(
        context: context,
        title: '关闭应用锁',
        content: '关闭后将不再要求输入密码解锁，确定吗？',
        confirmText: '关闭',
        isDangerous: true,
      );
      if (ok == true) {
        await state.appLock.disable();
        await state.refreshAppLock();
      }
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textWeak)),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, indent: 56, color: AppColors.divider);
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon, color: AppColors.primary),
      title: Text(title,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textMain)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textWeak)),
      value: value,
      activeTrackColor: AppColors.primary,
      onChanged: onChanged,
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textMain)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textWeak)),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_right, color: AppColors.textFaint),
      onTap: onTap,
    );
  }
}
