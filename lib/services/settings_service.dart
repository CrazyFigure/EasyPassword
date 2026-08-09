/// 设置服务：字体大小、底部栏自定义、默认 Tab、排序模式、显示全部开关
/// （需求 3.5.2 / 3.5.4 / 3.5.5）
library;

import 'dart:async';
import 'dart:convert';

import '../core/constants.dart';
import 'database.dart';

/// 底部栏 Tab 定义
class NavTab {
  final String id;
  final String label;
  const NavTab(this.id, this.label);

  static const password = NavTab('password', '密码');
  static const apikey = NavTab('apikey', 'API Key');
  static const search = NavTab('search', '搜索');
  static const ai = NavTab('ai', 'AI 识别');
  static const settings = NavTab('settings', '设置');

  static const all = [password, apikey, search, ai, settings];
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

/// 字号选项。
///
/// system 不写死倍率，运行时保留 Windows/Android 的系统文字缩放；standard
/// 明确锁定 1.0，因此界面上不再出现两个无法区分的“跟随系统”。
enum FontSizeMode {
  system('跟随系统', null),
  small('小', 0.85),
  standard('标准', 1.0),
  large('大', 1.15),
  extraLarge('特大', 1.3);

  const FontSizeMode(this.label, this.fixedScale);

  final String label;
  final double? fixedScale;

  /// 非 1.0 倍率继续沿用旧版数值格式，让尚未升级的其他设备仍能识别；
  /// system / standard 必须使用不同字符串，才能表达“跟随”与“固定 1.0”。
  String get storageValue => switch (this) {
        FontSizeMode.system => 'system',
        FontSizeMode.standard => 'standard',
        _ => fixedScale.toString(),
      };

  /// 兼容旧版本保存的数值；旧值 1.0 原本表示“跟随系统”。
  static FontSizeMode fromStored(String? value) {
    if (value == null || value.isEmpty || value == 'system' || value == '1.0') {
      return FontSizeMode.system;
    }
    for (final mode in FontSizeMode.values) {
      if (mode.name == value) return mode;
    }
    final legacyScale = double.tryParse(value);
    if (legacyScale == null) return FontSizeMode.system;
    return FontSizeMode.values.firstWhere(
      (mode) => mode.fixedScale == legacyScale,
      orElse: () => FontSizeMode.system,
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

  // ---------- 字体显示（字号跨端同步，字体族仅保存在当前设备） ----------
  Future<FontSizeMode> getFontSizeMode() async {
    final value = await DatabaseService.getSetting('font_scale');
    return FontSizeMode.fromStored(value);
  }

  Future<void> setFontSizeMode(FontSizeMode mode) async {
    await DatabaseService.setSetting('font_scale', mode.storageValue);
    _notifyChanged();
  }

  /// 当前设备选中的已安装字体；null 表示使用平台默认系统字体。
  Future<String?> getFontFamily() async {
    final value = await DatabaseService.getSetting('font_family');
    return value == null || value.trim().isEmpty ? null : value.trim();
  }

  /// 字体安装情况具有设备差异，因此字体族不加入 WebDAV 同步设置。
  Future<void> setFontFamily(String? family) async {
    await DatabaseService.setSetting('font_family', family?.trim() ?? '');
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

  // ---------- 分区排序模式（默认名称升序 / 自定义） ----------

  /// 读取指定分区的排序模式。
  ///
  /// 新键不存在时回退旧版共用键，使升级前的用户选择能同时迁移到两个分区；
  /// 后续修改只写对应分区，密码和 API Key 因而可以保持不同规则。
  Future<String> getSortMode(String type) async {
    final scopedValue =
        await DatabaseService.getSetting(_sortModeSettingKey(type));
    if (scopedValue != null && scopedValue.isNotEmpty) {
      return _normalizeSortMode(scopedValue);
    }
    final legacyValue = await DatabaseService.getSetting(DbKeys.sortMode);
    return _normalizeSortMode(legacyValue);
  }

  /// 仅更新指定分区的排序模式，非法值直接拒绝，避免界面与持久化状态失配。
  Future<void> setSortMode(String type, String mode) async {
    if (mode != 'name_asc' && mode != 'custom') {
      throw ArgumentError.value(mode, 'mode', '仅支持 name_asc 或 custom');
    }
    await DatabaseService.setSetting(_sortModeSettingKey(type), mode);
    _notifyChanged();
  }

  /// 根据条目类型映射独立设置键；未知类型属于调用错误，不能静默串到其他分区。
  String _sortModeSettingKey(String type) => switch (type) {
        ItemType.password => DbKeys.passwordSortMode,
        ItemType.apikey => DbKeys.apikeySortMode,
        _ => throw ArgumentError.value(type, 'type', '未知的条目类型'),
      };

  /// 同步或历史数据若含未知值，统一回退名称升序，保证排序行为可预测。
  String _normalizeSortMode(String? value) =>
      value == 'custom' ? 'custom' : 'name_asc';

  // ---------- 显示全部密码开关（1.1 / 2.1） ----------
  Future<bool> getRevealAll() async {
    final v = await DatabaseService.getSetting('reveal_all');
    return v == '1';
  }

  Future<void> setRevealAll(bool value) async {
    await DatabaseService.setSetting('reveal_all', value ? '1' : '0');
    _notifyChanged();
  }

  // ---------- 移动端安全键盘（跨设备同步） ----------

  /// 安全键盘默认开启；偏好加入加密快照，让多台移动设备保持一致。
  Future<bool> getSecureKeyboardEnabled() async {
    final value =
        await DatabaseService.getSetting(DbKeys.secureKeyboardEnabled);
    return value == null || value == '1';
  }

  Future<void> setSecureKeyboardEnabled(bool enabled) async {
    await DatabaseService.setSetting(
      DbKeys.secureKeyboardEnabled,
      enabled ? '1' : '0',
    );
    _notifyChanged();
  }

  // ---------- WebDAV 配置（3.5.3） ----------
  Future<({String url, String user, String pass, String path})?>
      getWebDavConfig() async {
    final url = await DatabaseService.getSetting(DbKeys.webdavUrl);
    if (url == null || url.isEmpty) return null;
    final user = await DatabaseService.getSetting(DbKeys.webdavUser) ?? '';
    final pass = await DatabaseService.getSetting(DbKeys.webdavPass) ?? '';
    final path = normalizeWebDavPath(
      await DatabaseService.getSetting(DbKeys.webdavPath),
    );
    return (url: url, user: user, pass: pass, path: path);
  }

  /// 保存连接信息前统一路径格式，确保各设备派生相同的快照加密身份。
  Future<void> setWebDavConfig(
    String url,
    String user,
    String pass,
    String path,
  ) async {
    await DatabaseService.setSetting(DbKeys.webdavUrl, url);
    await DatabaseService.setSetting(DbKeys.webdavUser, user);
    await DatabaseService.setSetting(DbKeys.webdavPass, pass);
    await DatabaseService.setSetting(
      DbKeys.webdavPath,
      normalizeWebDavPath(path),
    );
  }

  /// 总开关缺失时，仅对已经配置过 WebDAV 的老用户保持启用，避免升级后
  /// 中断原有同步；新安装且未配置的用户默认关闭。
  Future<bool> getWebDavEnabled() async {
    final value = await DatabaseService.getSetting(DbKeys.webdavEnabled);
    if (value != null) return value == '1';
    return await getWebDavConfig() != null;
  }

  Future<void> setWebDavEnabled(bool enabled) async {
    await DatabaseService.setSetting(
      DbKeys.webdavEnabled,
      enabled ? '1' : '0',
    );
  }

  /// 空值兼容旧配置并回退默认目录；其余路径统一为“/目录/子目录”格式。
  static String normalizeWebDavPath(String? value) {
    var path = value?.trim().replaceAll('\\', '/') ?? '';
    if (path.isEmpty) return WebDavDefaults.remotePath;
    final segments = path.split('/').where((part) => part.isNotEmpty).toList();
    if (segments.isEmpty) return WebDavDefaults.remotePath;
    if (segments.any((part) => part == '.' || part == '..')) {
      throw ArgumentError.value(value, 'value', 'WebDAV 路径不能包含 . 或 ..');
    }
    return '/${segments.join('/')}';
  }

  // ---------- 自动同步（仅本机，避免远端配置反向覆盖连接策略） ----------

  /// 修改后即时同步与前台定时同步总开关，配置 WebDAV 后默认开启。
  Future<bool> getAutoSyncEnabled() async {
    final value =
        await DatabaseService.getSetting(DbKeys.webdavAutoSyncEnabled);
    return value == null || value == '1';
  }

  Future<void> setAutoSyncEnabled(bool enabled) async {
    await DatabaseService.setSetting(
        DbKeys.webdavAutoSyncEnabled, enabled ? '1' : '0');
  }

  /// 前台定时同步间隔，默认 15 分钟；非法历史值自动回退默认值。
  Future<int> getAutoSyncIntervalMinutes() async {
    final value =
        await DatabaseService.getSetting(DbKeys.webdavAutoSyncInterval);
    final minutes = int.tryParse(value ?? '');
    return const {5, 15, 30, 60}.contains(minutes) ? minutes! : 15;
  }

  Future<void> setAutoSyncIntervalMinutes(int minutes) async {
    final safeMinutes = const {5, 15, 30, 60}.contains(minutes) ? minutes : 15;
    await DatabaseService.setSetting(
        DbKeys.webdavAutoSyncInterval, safeMinutes.toString());
  }
}
