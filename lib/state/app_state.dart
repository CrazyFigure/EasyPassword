/// 应用全局状态（Provider）：数据加载、Tab、显示开关、同步等
library;

import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../models/folder.dart';
import '../models/list_entry.dart';
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
  // 文件夹列表（各分区根目录下）
  List<Folder> passwordFolders = [];
  List<Folder> apikeyFolders = [];
  // 文件夹内条目数：folderId -> 条目数
  Map<String, int> folderCounts = {};
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

  /// 重新加载根目录列表与文件夹（文件夹内条目由文件夹页自行加载）
  Future<void> refresh() async {
    final byName = sortMode != 'custom';
    if (byName) {
      passwordItems = await data.listItemsByName('password');
      apikeyItems = await data.listItemsByName('apikey');
      passwordFolders = await data.listFoldersByName('password');
      apikeyFolders = await data.listFoldersByName('apikey');
    } else {
      passwordItems = await data.listItems('password');
      apikeyItems = await data.listItems('apikey');
      passwordFolders = await data.listFolders('password');
      apikeyFolders = await data.listFolders('apikey');
    }
    folderCounts = {
      ...await data.countItemsByFolder('password'),
      ...await data.countItemsByFolder('apikey'),
    };
    notifyListeners();
  }

  /// 某分区根列表的最终显示顺序（文件夹 + 条目混合）。
  ///
  /// - 按名称排序：文件夹整体排在条目之前，两组各自按名称升序；
  /// - 自定义排序：两者共用一套 sort_order，可任意交叉排列。
  List<ListEntry> rootEntries(String type) {
    final isApi = type == ItemType.apikey;
    final folders = isApi ? apikeyFolders : passwordFolders;
    final items = isApi ? apikeyItems : passwordItems;
    if (sortMode == 'custom') {
      final entries = <ListEntry>[
        for (final f in folders) ListEntry.ofFolder(f),
        for (final i in items) ListEntry.ofItem(i),
      ];
      // 序号相同时（如历史数据重号）让文件夹稳定靠前，避免顺序抖动
      entries.sort((a, b) {
        final c = a.sortOrder.compareTo(b.sortOrder);
        if (c != 0) return c;
        if (a.isFolder != b.isFolder) return a.isFolder ? -1 : 1;
        return 0;
      });
      return entries;
    }
    // 名称排序：文件夹恒在前，各组内部已由 SQL 按名称排好
    return [
      for (final f in folders) ListEntry.ofFolder(f),
      for (final i in items) ListEntry.ofItem(i),
    ];
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
