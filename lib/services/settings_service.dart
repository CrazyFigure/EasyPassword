/// 设置服务：字体大小、底部栏自定义、默认 Tab、排序模式、显示全部开关
/// （需求 3.5.2 / 3.5.4 / 3.5.5）
library;

import 'dart:async';
import 'dart:convert';

import 'database.dart';

/// 底部栏 Tab 定义
class NavTab {
  final String id;
  final String label;
  const NavTab(this.id, this.label);

  static const password = NavTab('password', '密码');
  static const apikey = NavTab('apikey', 'API Key');
  static const search = NavTab('search', '搜索');
  static const settings = NavTab('settings', '设置');

  static const all = [password, apikey, search, settings];
}

class TabConfig {
  final List<String> visibleIds; // 按显示顺序排列
  final String defaultTabId; // 启动默认打开的 tab

  const TabConfig({required this.visibleIds, required this.defaultTabId});

  static const defaultConfig = TabConfig(
    visibleIds: ['password', 'apikey', 'search', 'settings'],
    defaultTabId: 'password',
  );

  Map<String, dynamic> toJson() =>
      {'visible': visibleIds, 'default': defaultTabId};

  factory TabConfig.fromJson(Map<String, dynamic> json) {
    return TabConfig(
      visibleIds: (json['visible'] as List?)?.cast<String>() ??
          defaultConfig.visibleIds,
      defaultTabId: (json['default'] as String?) ?? 'password',
    );
  }
}

class SettingsService {
  /// 可同步设置保存后的通知入口，由 AppState 防抖后触发 WebDAV 自动同步。
  Future<void> Function()? onChanged;

  void _notifyChanged() {
    final callback = onChanged;
    if (callback != null) unawaited(callback());
  }

  // ---------- 字体大小（3.5.2，默认跟随系统=1.0） ----------
  Future<double> getFontScale() async {
    final v = await DatabaseService.getSetting('font_scale');
    if (v == null || v.isEmpty) return 1.0;
    return double.tryParse(v) ?? 1.0;
  }

  Future<void> setFontScale(double scale) async {
    await DatabaseService.setSetting('font_scale', scale.toString());
    _notifyChanged();
  }

  // ---------- 底部栏自定义（3.5.4） ----------
  Future<TabConfig> getTabConfig() async {
    final v = await DatabaseService.getSetting('tab_visibility');
    if (v == null || v.isEmpty) return TabConfig.defaultConfig;
    try {
      return TabConfig.fromJson(jsonDecode(v) as Map<String, dynamic>);
    } catch (_) {
      return TabConfig.defaultConfig;
    }
  }

  Future<void> setTabConfig(TabConfig config) async {
    await DatabaseService.setSetting(
        'tab_visibility', jsonEncode(config.toJson()));
    _notifyChanged();
  }

  /// 切换某个 tab 显隐
  Future<TabConfig> toggleTab(String tabId) async {
    final cfg = await getTabConfig();
    final visible = List<String>.from(cfg.visibleIds);
    if (visible.contains(tabId)) {
      visible.remove(tabId);
    } else {
      visible.add(tabId);
    }
    var defaultTab = cfg.defaultTabId;
    if (defaultTab == tabId && !visible.contains(tabId)) {
      defaultTab = visible.isNotEmpty ? visible.first : 'password';
    }
    final next = TabConfig(visibleIds: visible, defaultTabId: defaultTab);
    await setTabConfig(next);
    return next;
  }

  /// 调整 tab 顺序
  Future<TabConfig> reorderTabs(List<String> orderedIds) async {
    final cfg = await getTabConfig();
    final next = TabConfig(
      visibleIds: orderedIds,
      defaultTabId: cfg.defaultTabId,
    );
    await setTabConfig(next);
    return next;
  }

  /// 设置默认打开 tab
  Future<TabConfig> setDefaultTab(String tabId) async {
    final cfg = await getTabConfig();
    final next = TabConfig(visibleIds: cfg.visibleIds, defaultTabId: tabId);
    await setTabConfig(next);
    return next;
  }

  // ---------- 排序模式（3.5.5：默认名称升序 / 自定义） ----------
  Future<String> getSortMode() async {
    final v = await DatabaseService.getSetting('sort_mode');
    return (v == null || v.isEmpty) ? 'name_asc' : v;
  }

  Future<void> setSortMode(String mode) async {
    await DatabaseService.setSetting('sort_mode', mode);
    _notifyChanged();
  }

  // ---------- 显示全部密码开关（1.1 / 2.1） ----------
  Future<bool> getRevealAll() async {
    final v = await DatabaseService.getSetting('reveal_all');
    return v == '1';
  }

  Future<void> setRevealAll(bool value) async {
    await DatabaseService.setSetting('reveal_all', value ? '1' : '0');
    _notifyChanged();
  }

  // ---------- WebDAV 配置（3.5.3） ----------
  Future<({String url, String user, String pass})?> getWebDavConfig() async {
    final url = await DatabaseService.getSetting('webdav_url');
    if (url == null || url.isEmpty) return null;
    final user = await DatabaseService.getSetting('webdav_username') ?? '';
    final pass = await DatabaseService.getSetting('webdav_password') ?? '';
    return (url: url, user: user, pass: pass);
  }

  Future<void> setWebDavConfig(String url, String user, String pass) async {
    await DatabaseService.setSetting('webdav_url', url);
    await DatabaseService.setSetting('webdav_username', user);
    await DatabaseService.setSetting('webdav_password', pass);
  }

  // ---------- 自动同步（仅本机，避免远端配置反向覆盖连接策略） ----------

  /// 修改后即时同步与前台定时同步总开关，配置 WebDAV 后默认开启。
  Future<bool> getAutoSyncEnabled() async {
    final value = await DatabaseService.getSetting('webdav_auto_sync_enabled');
    return value == null || value == '1';
  }

  Future<void> setAutoSyncEnabled(bool enabled) async {
    await DatabaseService.setSetting(
        'webdav_auto_sync_enabled', enabled ? '1' : '0');
  }

  /// 前台定时同步间隔，默认 15 分钟；非法历史值自动回退默认值。
  Future<int> getAutoSyncIntervalMinutes() async {
    final value = await DatabaseService.getSetting('webdav_auto_sync_interval');
    final minutes = int.tryParse(value ?? '');
    return const {5, 15, 30, 60}.contains(minutes) ? minutes! : 15;
  }

  Future<void> setAutoSyncIntervalMinutes(int minutes) async {
    final safeMinutes = const {5, 15, 30, 60}.contains(minutes) ? minutes : 15;
    await DatabaseService.setSetting(
        'webdav_auto_sync_interval', safeMinutes.toString());
  }
}
