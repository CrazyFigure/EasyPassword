/// 应用全局状态（Provider）：数据加载、Tab、显示开关、同步等
library;

import 'package:flutter/foundation.dart';

import '../models/password_item.dart';
import '../services/app_lock_service.dart';
import '../services/crypto_service.dart';
import '../services/data_service.dart';
import '../services/search_service.dart';
import '../services/settings_service.dart';
import '../services/webdav_service.dart';

class AppState extends ChangeNotifier {
  // 服务实例
  late final CryptoService crypto;
  late final DataService data;
  late final SearchService search;
  late final SettingsService settings;
  late final AppLockService appLock;
  late final WebDavService webdav;

  // 当前状态
  bool initialized = false;
  bool locked = true; // 应用锁是否锁定
  bool appLockEnabled = false; // 应用锁配置是否开启（同步缓存）
  double fontScale = 1.0; // 字体缩放（默认 1.0 = 跟随系统）
  String sortMode = 'name_asc'; // 排序模式：name_asc | custom
  String currentTab = 'password';
  List<PasswordItem> passwordItems = [];
  List<PasswordItem> apikeyItems = [];
  bool revealAll = false;
  bool syncing = false;
  String? syncMessage;
  TabConfig tabConfig = TabConfig.defaultConfig; // 底部栏配置（缓存）

  AppState() {
    crypto = CryptoService();
    data = DataService(crypto);
    search = SearchService(data, crypto);
    settings = SettingsService();
    appLock = AppLockService(crypto);
    webdav = WebDavService(crypto, data);
  }

  /// 初始化：读取设置与数据
  Future<void> init() async {
    if (initialized) return;
    await appLock.initKey();
    appLockEnabled = await appLock.isEnabled();
    // 未开启应用锁时直接进入主界面；开启时显示锁屏
    locked = appLockEnabled;
    tabConfig = await settings.getTabConfig();
    currentTab = tabConfig.defaultTabId;
    revealAll = await settings.getRevealAll();
    fontScale = await settings.getFontScale();
    sortMode = await settings.getSortMode();
    await refresh();
    initialized = true;
    notifyListeners();
  }

  /// 更新字体缩放并缓存
  Future<void> updateFontScale(double scale) async {
    fontScale = scale;
    await settings.setFontScale(scale);
    notifyListeners();
  }

  /// 更新排序模式并刷新列表
  Future<void> updateSortMode(String mode) async {
    sortMode = mode;
    await settings.setSortMode(mode);
    await refresh();
  }

  /// 刷新应用锁状态缓存
  Future<void> refreshAppLock() async {
    appLockEnabled = await appLock.isEnabled();
    notifyListeners();
  }

  /// 底部可见 Tab（按用户配置的顺序）
  List<NavTab> get currentVisibleTabs {
    return [
      for (final id in tabConfig.visibleIds)
        NavTab.all.firstWhere((t) => t.id == id, orElse: () => NavTab(id, id)),
    ];
  }

  /// 更新底部栏配置并刷新
  Future<void> updateTabConfig(TabConfig config) async {
    tabConfig = config;
    await settings.setTabConfig(config);
    notifyListeners();
  }

  /// 重新加载列表
  Future<void> refresh() async {
    if (sortMode == 'custom') {
      passwordItems = await data.listItems('password');
      apikeyItems = await data.listItems('apikey');
    } else {
      passwordItems = await data.listItemsByName('password');
      apikeyItems = await data.listItemsByName('apikey');
    }
    notifyListeners();
  }

  /// 设置当前 tab
  void setTab(String tab) {
    if (currentTab == tab) return;
    currentTab = tab;
    notifyListeners();
  }

  /// 切换显示全部开关
  Future<void> toggleRevealAll() async {
    revealAll = !revealAll;
    await settings.setRevealAll(revealAll);
    notifyListeners();
  }

  /// 同步（WebDAV 已配置时）
  Future<void> syncNow() async {
    final cfg = await settings.getWebDavConfig();
    if (cfg == null) {
      syncMessage = '尚未配置 WebDAV';
      notifyListeners();
      return;
    }
    syncing = true;
    syncMessage = '同步中...';
    notifyListeners();
    try {
      final summary = await webdav.syncAll(cfg.url, cfg.user, cfg.pass);
      syncMessage = summary.merged > 0
          ? '同步完成，合并 ${summary.merged} 条'
          : '同步完成';
      await refresh();
    } catch (e) {
      syncMessage =
          '同步失败：${e.toString().replaceFirst('Exception: ', '')}';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  /// 解锁
  Future<bool> unlock(String pin) async {
    final ok = await appLock.verify(pin);
    if (ok) {
      await appLock.unlockWithPin(pin);
      locked = false;
      notifyListeners();
    }
    return ok;
  }
}
