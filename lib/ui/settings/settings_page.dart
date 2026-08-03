/// 设置页：应用锁 / 字体大小 / 底部栏自定义 / WebDAV 同步 / 关于
/// （需求 3.5.1 - 3.5.5）
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../state/app_state.dart';
import 'app_lock_setup.dart';
import 'font_size_setting.dart';
import 'tab_customize_sheet.dart';
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
        _SectionLabel('安全'),
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
                MaterialPageRoute(
                    builder: (_) => const AppLockSetupPage()),
              );
            },
          ),
        ]),
        const SizedBox(height: 16),
        // ===== 显示 =====
        const _SectionLabel('显示'),
        _SettingsCard(children: [
          _ActionTile(
            icon: Icons.text_fields,
            title: '字体大小',
            subtitle: '默认跟随系统',
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
            onTap: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
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
            subtitle: state.syncMessage ?? '配置服务器以多端同步',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WebDavSetupPage()),
            ),
          ),
          if (state.syncMessage != null) ...[
            const _Divider(),
            _ActionTile(
              icon: Icons.cloud_sync_outlined,
              title: '立即同步',
              subtitle: state.syncing ? '同步中...' : '拉取并推送加密快照',
              onTap: state.syncing ? null : () => state.syncNow(),
            ),
          ],
        ]),
        const SizedBox(height: 16),
        // ===== 关于 =====
        const _SectionLabel('关于'),
        _SettingsCard(children: [
          const _ActionTile(
            icon: Icons.info_outline,
            title: '版本',
            subtitle: 'EasyPassword v1.0.0 · Android + Windows',
            onTap: null,
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
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('关闭应用锁'),
          content: const Text('关闭后将不再要求输入密码解锁，确定吗？'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await state.appLock.disable();
        state.refresh();
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
    return const Divider(
        height: 1, indent: 56, color: AppColors.divider);
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
