/// 应用全局状态（Provider）：数据加载、Tab、显示开关、同步等
library;

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../core/constants.dart';
import '../models/folder.dart';
import '../models/list_entry.dart';
import '../models/password_item.dart';
import '../services/app_lock_service.dart';
import '../services/crypto_service.dart';
import '../services/data_service.dart';
import '../services/database.dart';
import '../services/search_service.dart';
import '../services/settings_service.dart';
import '../services/webdav_service.dart';

class AppState extends ChangeNotifier with WidgetsBindingObserver {
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
  FontSizeMode fontSizeMode = FontSizeMode.system; // system 保留平台文字缩放
  String? fontFamily; // null 使用 Windows/Android 平台默认系统字体
  // 两类条目独立缓存排序模式，避免在一个分区切换后影响另一个分区。
  String passwordSortMode = 'name_asc';
  String apikeySortMode = 'name_asc';
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
  bool autoSyncEnabled = true; // 修改后即时同步与前台定时同步总开关
  int autoSyncIntervalMinutes = 15; // 前台定时拉取其他设备变更的间隔
  DateTime? lastSyncAt; // 最近一次成功同步时间
  TabConfig tabConfig = TabConfig.defaultConfig; // 底部栏配置（缓存）

  Timer? _changeSyncTimer; // 连续编辑防抖，避免每个字段保存都发起独立请求
  Timer? _periodicSyncTimer; // 应用运行期间的定时同步任务
  bool _syncQueued = false; // 同步过程中又发生修改时，结束后追加一轮
  Future<void>? _initializationFuture; // 合并并发初始化；失败后清空以支持界面重试
  bool _observingLifecycle = false; // 防止初始化重试时重复注册生命周期观察者

  AppState() {
    crypto = CryptoService();
    data = DataService(crypto);
    search = SearchService(data, crypto);
    settings = SettingsService();
    appLock = AppLockService(crypto);
    webdav = WebDavService(crypto, data);
    // 三类本地修改统一进入同一防抖队列，保存本身不等待网络。
    data.onChanged = _onLocalChanged;
    settings.onChanged = _onLocalChanged;
    appLock.onChanged = _onLocalChanged;
  }

  /// 初始化：读取设置与数据。同一时刻只执行一次；失败时保留服务实例并允许重试。
  Future<void> init() {
    if (initialized) return Future.value();
    return _initializationFuture ??= _initializeWithReset();
  }

  /// 包装实际初始化流程，确保成功或失败后都释放 Future 缓存。
  Future<void> _initializeWithReset() async {
    try {
      await _initialize();
    } finally {
      _initializationFuture = null;
    }
  }

  /// 实际初始化流程；任何步骤失败都回滚运行态标记，避免重试误判为成功。
  Future<void> _initialize() async {
    if (!_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    }
    try {
      await appLock.initKey();
      appLockEnabled = await appLock.isEnabled();
      // 未开启应用锁时直接进入主界面；开启时显示锁屏
      locked = appLockEnabled;
      tabConfig = await settings.getTabConfig();
      currentTab = tabConfig.defaultTabId;
      revealAll = await settings.getRevealAll();
      fontSizeMode = await settings.getFontSizeMode();
      fontFamily = await settings.getFontFamily();
      passwordSortMode = await settings.getSortMode(ItemType.password);
      apikeySortMode = await settings.getSortMode(ItemType.apikey);
      autoSyncEnabled = await settings.getAutoSyncEnabled();
      autoSyncIntervalMinutes = await settings.getAutoSyncIntervalMinutes();
      final lastSyncValue =
          await DatabaseService.getSetting('sync_last_success');
      final lastSyncMillis = int.tryParse(lastSyncValue ?? '');
      if (lastSyncMillis != null) {
        lastSyncAt = DateTime.fromMillisecondsSinceEpoch(lastSyncMillis);
      }
      await refresh();
      initialized = true;
      await _restartPeriodicSync();
      notifyListeners();
      // 启动后异步拉取一次，及时接收应用关闭期间其他设备的修改。
      _scheduleAutomaticSync(const Duration(milliseconds: 800));
    } catch (_) {
      initialized = false;
      _changeSyncTimer?.cancel();
      _periodicSyncTimer?.cancel();
      rethrow;
    }
  }

  /// 仅预览字体设置，不落库；设置页取消或返回时可无缝恢复原值。
  void previewTypography(FontSizeMode sizeMode, String? family) {
    fontSizeMode = sizeMode;
    fontFamily = family;
    notifyListeners();
  }

  /// 保存字号与当前设备字体。字号参与多端同步，字体族因安装差异仅本机保存。
  Future<void> saveTypography(FontSizeMode sizeMode, String? family) async {
    fontSizeMode = sizeMode;
    fontFamily = family;
    await settings.setFontSizeMode(sizeMode);
    await settings.setFontFamily(family);
    notifyListeners();
  }

  /// 获取指定分区当前排序模式；调用方统一走这里，避免误用另一分区状态。
  String sortModeFor(String type) => switch (type) {
        ItemType.password => passwordSortMode,
        ItemType.apikey => apikeySortMode,
        _ => throw ArgumentError.value(type, 'type', '未知的条目类型'),
      };

  /// 仅更新指定分区排序模式并刷新两类缓存，确保返回列表页时状态一致。
  Future<void> updateSortMode(String type, String mode) async {
    switch (type) {
      case ItemType.password:
        passwordSortMode = mode;
      case ItemType.apikey:
        apikeySortMode = mode;
      default:
        throw ArgumentError.value(type, 'type', '未知的条目类型');
    }
    await settings.setSortMode(type, mode);
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
    // 两个分区分别选择查询顺序，允许密码按名称、API Key 按自定义顺序展示。
    final passwordByName = passwordSortMode != 'custom';
    final apikeyByName = apikeySortMode != 'custom';
    passwordItems = passwordByName
        ? await data.listItemsByName(ItemType.password)
        : await data.listItems(ItemType.password);
    passwordFolders = passwordByName
        ? await data.listFoldersByName(ItemType.password)
        : await data.listFolders(ItemType.password);
    apikeyItems = apikeyByName
        ? await data.listItemsByName(ItemType.apikey)
        : await data.listItems(ItemType.apikey);
    apikeyFolders = apikeyByName
        ? await data.listFoldersByName(ItemType.apikey)
        : await data.listFolders(ItemType.apikey);
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
    if (sortModeFor(type) == 'custom') {
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

  /// 保存 WebDAV 配置并立即验证/创建 EasyPassword 远端文件夹。
  Future<void> saveWebDavConfig(
      String url, String username, String password) async {
    await webdav.testConnection(url, username, password);
    await settings.setWebDavConfig(url, username, password);
    await _restartPeriodicSync();
    _scheduleAutomaticSync(const Duration(milliseconds: 300));
  }

  /// 更新自动同步策略。关闭后仍可使用三种手动同步按钮。
  Future<void> updateAutoSync({required bool enabled, int? minutes}) async {
    autoSyncEnabled = enabled;
    if (minutes != null) {
      autoSyncIntervalMinutes = minutes;
      await settings.setAutoSyncIntervalMinutes(minutes);
    }
    await settings.setAutoSyncEnabled(enabled);
    await _restartPeriodicSync();
    notifyListeners();
    if (enabled) _scheduleAutomaticSync(const Duration(milliseconds: 300));
  }

  /// 执行三种同步模式。自动模式逐行合并；两个覆盖模式由界面二次确认。
  Future<void> syncNow({
    WebDavSyncMode mode = WebDavSyncMode.automatic,
    bool background = false,
  }) async {
    final cfg = await settings.getWebDavConfig();
    if (cfg == null) {
      syncMessage = '尚未配置 WebDAV';
      notifyListeners();
      return;
    }
    if (syncing) {
      _syncQueued = true;
      return;
    }
    syncing = true;
    if (!background) syncMessage = '同步中...';
    notifyListeners();
    try {
      final SyncSummary summary;
      switch (mode) {
        case WebDavSyncMode.localToRemote:
          summary = await webdav.overwriteRemote(cfg.url, cfg.user, cfg.pass);
          break;
        case WebDavSyncMode.remoteToLocal:
          summary = await webdav.overwriteLocal(cfg.url, cfg.user, cfg.pass);
          break;
        case WebDavSyncMode.automatic:
          summary = await webdav.syncAll(cfg.url, cfg.user, cfg.pass);
          break;
      }
      lastSyncAt = DateTime.now();
      await DatabaseService.setSetting(
        'sync_last_success',
        lastSyncAt!.millisecondsSinceEpoch.toString(),
      );
      syncMessage = switch (mode) {
        WebDavSyncMode.localToRemote => '本地数据已覆盖远端',
        WebDavSyncMode.remoteToLocal => '远端数据已覆盖本地',
        WebDavSyncMode.automatic =>
          summary.merged > 0 ? '自动同步完成，合并 ${summary.merged} 个条目' : '自动同步完成',
      };
      await _reloadAfterSync();
    } catch (e) {
      final prefix = background ? '自动同步失败' : '同步失败';
      syncMessage = '$prefix：${e.toString().replaceFirst('Exception: ', '')}';
    } finally {
      syncing = false;
      notifyListeners();
      if (_syncQueued) {
        _syncQueued = false;
        _scheduleAutomaticSync(const Duration(milliseconds: 500));
      }
    }
  }

  /// 远端设置可能改变字体、导航、排序和应用锁，合并后必须整体刷新缓存。
  Future<void> _reloadAfterSync() async {
    final wasLockEnabled = appLockEnabled;
    appLockEnabled = await appLock.isEnabled();
    tabConfig = await settings.getTabConfig();
    revealAll = await settings.getRevealAll();
    fontSizeMode = await settings.getFontSizeMode();
    passwordSortMode = await settings.getSortMode(ItemType.password);
    apikeySortMode = await settings.getSortMode(ItemType.apikey);
    if (!tabConfig.visibleIds.contains(currentTab)) {
      currentTab = tabConfig.defaultTabId;
    }
    // 其他设备切换应用锁时本机立即跟随；锁状态未变化则不打断已解锁会话。
    if (wasLockEnabled != appLockEnabled) locked = appLockEnabled;
    await refresh();
  }

  /// 每次业务或可同步设置变更后延迟一小段时间合并发送；断网失败时日志
  /// 会保留，定时任务或恢复到前台后继续重试。
  Future<void> _onLocalChanged() async {
    if (!initialized || !autoSyncEnabled) return;
    if (syncing) {
      _syncQueued = true;
      return;
    }
    _scheduleAutomaticSync(const Duration(seconds: 2));
  }

  void _scheduleAutomaticSync(Duration delay) {
    if (!initialized || !autoSyncEnabled) return;
    _changeSyncTimer?.cancel();
    _changeSyncTimer = Timer(delay, () async {
      final cfg = await settings.getWebDavConfig();
      if (cfg == null || !autoSyncEnabled) return;
      await syncNow(background: true);
    });
  }

  /// 应用运行期间周期拉取远端，既重试离线修改，也接收其他设备的变化。
  Future<void> _restartPeriodicSync() async {
    _periodicSyncTimer?.cancel();
    if (!initialized || !autoSyncEnabled) return;
    final cfg = await settings.getWebDavConfig();
    if (cfg == null) return;
    _periodicSyncTimer = Timer.periodic(
      Duration(minutes: autoSyncIntervalMinutes),
      (_) => unawaited(syncNow(background: true)),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleAutomaticSync(const Duration(milliseconds: 500));
    }
  }

  /// 解锁
  Future<bool> unlock(String pin) async {
    final ok = await appLock.verify(pin);
    if (ok) {
      await appLock.unlockWithPin(pin);
      locked = false;
      notifyListeners();
      // 解锁后已具备旧快照迁移密钥，立即重试一次自动同步完成格式升级。
      _scheduleAutomaticSync(const Duration(milliseconds: 500));
    }
    return ok;
  }

  @override
  void dispose() {
    if (_observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _changeSyncTimer?.cancel();
    _periodicSyncTimer?.cancel();
    super.dispose();
  }
}
