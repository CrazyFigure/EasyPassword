/// 更新检测服务：查询 GitHub 最新 Release 并做语义版本比较。
///
/// 代理处理策略对齐 MyTerminal（参考其 commands.rs 的 check_for_updates）：
/// 1. 首次请求走系统代理（Windows 读取注册表代理；其他平台默认走环境变量策略）；
/// 2. 网络错误（代理不可达等）→ 回退直连重试一次；
/// 3. 403（代理节点数据中心 IP 常被 GitHub API 风控）→ 回退直连重试一次；
/// 3.5 仍为 403 时改走 github.com 的 releases/latest 302 跳转拿版本号：
///    api.github.com 未认证配额按出口 IP 计（60 次/小时），运营商 NAT、公司出口、
///    VPN 出口都是多人共享 IP，配额常被他人占满，换代理重试同一端点无用；
///    而网页站点的 302 不吃该配额，代价是拿不到更新说明与安装包信息；
/// 4. 403 需区分：响应头 X-RateLimit-Remaining 为 0 才确认是 API 配额耗尽，
///    否则多为代理/安全策略拦截，不应误报成限流；
/// 5. 版本比较只做保守语义比较：tag 含非数字段时视为无更新，避免误报。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:win32_registry/win32_registry.dart';

import '../core/constants.dart';

/// 更新请求注入点：生产环境按是否使用系统代理发起请求，测试可返回固定响应。
typedef UpdateFetcher = Future<http.Response> Function(bool useSystemProxy);

/// 发布产物所属平台，决定从 Release assets 里挑哪种扩展名的安装包。
/// 独立于 [Platform] 是为了可注入：测试跑在 Linux/macOS 宿主上时，
/// 直接读 Platform 会让 Windows/Android 的挑包逻辑变成不可测。
enum UpdateTargetPlatform {
  windows('.exe'),
  android('.apk'),

  /// 桌面 Linux/macOS 等没有发布产物的平台，不提供应用内安装。
  unsupported(null);

  const UpdateTargetPlatform(this.installerExtension);

  /// 当前平台安装包的扩展名；无发布产物时为 null。
  final String? installerExtension;

  /// 按实际运行平台推导，供生产代码默认使用。
  static UpdateTargetPlatform get current {
    if (Platform.isWindows) return UpdateTargetPlatform.windows;
    if (Platform.isAndroid) return UpdateTargetPlatform.android;
    return UpdateTargetPlatform.unsupported;
  }
}

/// 兜底注入点：返回 releases/latest 的 302 Location 响应头（拿不到时返回 null）。
typedef UpdateLocationFetcher = Future<String?> Function();

/// 更新检查结果
class UpdateCheckResult {
  final String currentVersion;
  final String latestVersion;
  final String releaseName;
  final String releaseUrl;
  final bool updateAvailable;
  final String? publishedAt;
  final String? releaseBody;
  final String? installerAssetName;

  /// Windows 安装包直链下载地址。302 兜底路径拿不到 assets 时为 null，
  /// 此时界面只能引导用户去 Release 页面手动下载。
  final String? installerDownloadUrl;

  /// 安装包字节数，用于下载进度展示；未知时为 null。
  final int? installerSize;

  /// 该结果对应的发布平台，决定应用内安装是否可用。
  final UpdateTargetPlatform targetPlatform;

  const UpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseUrl,
    required this.updateAvailable,
    this.publishedAt,
    this.releaseBody,
    this.installerAssetName,
    this.installerDownloadUrl,
    this.installerSize,
    this.targetPlatform = UpdateTargetPlatform.unsupported,
  });

  /// 是否具备应用内直接下载安装的条件：只有 Windows/Android 有发布产物，
  /// 且必须拿到了 asset 直链（302 兜底路径没有 assets 信息）。
  bool get canInstallInApp =>
      targetPlatform.installerExtension != null &&
      installerDownloadUrl != null &&
      installerDownloadUrl!.isNotEmpty;
}

/// 更新检查异常。[code] 对齐 MyTerminal 的错误分类：
/// network / rate_limited / forbidden / http_status / parse
class UpdateCheckException implements Exception {
  final String code;

  /// 附加信息：限流时的配额重置 Unix 时间戳（秒），或 HTTP 状态码等
  final String detail;
  const UpdateCheckException(this.code, [this.detail = '']);

  @override
  String toString() => 'UpdateCheckException($code, $detail)';
}

/// 安装包下载异常。[code] 取值：
/// network（连接失败）/ http_status（响应码异常）/ io（磁盘写入失败）/ cancelled（用户取消）
class UpdateDownloadException implements Exception {
  final String code;
  final String detail;
  const UpdateDownloadException(this.code, [this.detail = '']);

  @override
  String toString() => 'UpdateDownloadException($code, $detail)';
}

/// 启动安装异常。[code] 取值：
/// missing_file（安装包丢失）/ launch_failed（拉起失败，含 UAC 被拒）/
/// permission_denied（Android 未授权安装未知应用）/ unsupported_platform
class UpdateInstallException implements Exception {
  final String code;
  final String detail;
  const UpdateInstallException(this.code, [this.detail = '']);

  @override
  String toString() => 'UpdateInstallException($code, $detail)';
}

class UpdateService {
  /// 原生通道：Android 侧用 FileProvider 把 APK 交给系统包安装器。
  static const _platform = MethodChannel('easypassword/updater');

  /// 连接超时（对齐 MyTerminal UPDATE_HTTP_CONNECT_TIMEOUT 量级）
  static const _connectTimeout = Duration(seconds: 10);

  /// 读取超时（对齐 MyTerminal UPDATE_HTTP_READ_TIMEOUT = 40s）
  static const _readTimeout = Duration(seconds: 40);

  static const _userAgent = 'EasyPassword';

  final String currentVersion;
  final UpdateFetcher? _fetcher;
  final UpdateLocationFetcher? _locationFetcher;

  /// 挑选安装包时依据的平台。默认取实际运行平台，测试可显式指定，
  /// 使 Windows/Android 的挑包逻辑在任意宿主上都能验证。
  final UpdateTargetPlatform targetPlatform;

  /// [currentVersion] 默认取 Flutter 构建产物的真实包版本；
  /// [fetcher]、[locationFetcher] 与 [targetPlatform] 仅用于隔离测试。
  UpdateService({
    String? currentVersion,
    UpdateFetcher? fetcher,
    UpdateLocationFetcher? locationFetcher,
    UpdateTargetPlatform? targetPlatform,
  })  : currentVersion = currentVersion ?? AppInfo.currentVersion,
        _fetcher = fetcher,
        _locationFetcher = locationFetcher,
        targetPlatform = targetPlatform ?? UpdateTargetPlatform.current;

  /// 检测是否有新版本。失败时抛出 [UpdateCheckException]。
  Future<UpdateCheckResult> check() async {
    http.Response response;
    // 首次走系统代理；网络错误（代理不可达等）回退直连重试一次
    try {
      response = await _request(useSystemProxy: true);
    } catch (firstError) {
      try {
        response = await _request(useSystemProxy: false);
      } catch (secondError) {
        throw UpdateCheckException(
          'network',
          '$firstError; direct: $secondError',
        );
      }
    }
    // 403：代理节点被 GitHub API 风控 → 直连重试一次
    if (response.statusCode == 403) {
      try {
        response = await _request(useSystemProxy: false);
      } catch (error) {
        throw UpdateCheckException('network', error.toString());
      }
    }
    if (response.statusCode == 403) {
      // 区分限流与拦截：X-RateLimit-Remaining 为 0 才确认为配额耗尽
      final remaining =
          int.tryParse(response.headers['x-ratelimit-remaining'] ?? '') ?? -1;
      // API 配额是按出口 IP 计的（未认证 60 次/小时）。移动网络的运营商 NAT、
      // 公司出口、VPN 出口都是多人共享同一 IP，配额常被他人占满，重试同一端点
      // 无意义。此时改走 github.com 的 releases/latest 302 跳转拿版本号——
      // 那是网页站点，不吃 API 配额，只是拿不到更新说明与安装包信息。
      final fallback = await _checkViaRedirect();
      if (fallback != null) return fallback;
      if (remaining == 0) {
        throw UpdateCheckException(
            'rate_limited', response.headers['x-ratelimit-reset'] ?? '');
      }
      throw const UpdateCheckException('forbidden');
    }
    if (response.statusCode != 200) {
      throw UpdateCheckException('http_status', '${response.statusCode}');
    }
    // 解析 Release 元数据
    try {
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final latestTag = data['tag_name'] as String? ?? '';
      final latestVersion = latestTag.replaceFirst(RegExp(r'^[vV]'), '');
      // Release 或安装包版本不是纯数字语义版本时必须明确报解析错误，不能误报最新版。
      if (_parseVersion(latestVersion) == null ||
          _parseVersion(currentVersion) == null) {
        throw const UpdateCheckException('parse', 'invalid_version');
      }
      final htmlUrl = data['html_url'] as String? ?? '';
      final installerInfo = _pickInstallerAsset(data['assets']);
      return UpdateCheckResult(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        releaseName: data['name'] as String? ?? latestTag,
        releaseUrl: htmlUrl.isNotEmpty ? htmlUrl : AppInfo.releasePageUrl,
        publishedAt: data['published_at'] as String?,
        releaseBody: data['body'] as String?,
        installerAssetName: installerInfo?.name,
        installerDownloadUrl: installerInfo?.downloadUrl,
        installerSize: installerInfo?.size,
        targetPlatform: targetPlatform,
        updateAvailable: _isNewerVersion(latestVersion, currentVersion),
      );
    } on UpdateCheckException {
      rethrow;
    } catch (e) {
      throw UpdateCheckException('parse', e.toString());
    }
  }

  /// 统一分派生产网络请求与测试注入请求，保证代理回退逻辑本身也可测试。
  Future<http.Response> _request({required bool useSystemProxy}) {
    final fetcher = _fetcher;
    if (fetcher != null) return fetcher(useSystemProxy);
    return _fetch(useSystemProxy: useSystemProxy);
  }

  /// 发起请求。[useSystemProxy] 为 true 时优先使用 Windows 系统代理；
  /// false 时强制直连（no_proxy 语义）。
  Future<http.Response> _fetch({required bool useSystemProxy}) async {
    final client = await _buildClient(useSystemProxy: useSystemProxy);
    try {
      // GitHub API 要求明确 User-Agent
      return await client.get(
        Uri.parse(AppInfo.releaseApiUrl),
        headers: {'User-Agent': _userAgent},
      ).timeout(_readTimeout);
    } finally {
      client.close();
    }
  }

  /// 按代理策略构造 HTTP 客户端，供 API 请求与 302 兜底共用。
  Future<IOClient> _buildClient({required bool useSystemProxy}) async {
    final hc = HttpClient();
    if (!useSystemProxy) {
      // 直连：忽略系统代理，避免把代理服务器的拒绝误报成 GitHub 限流
      hc.findProxy = (_) => 'DIRECT';
    } else {
      // 走系统代理：Windows 从注册表读取，其他平台保持默认（环境变量）策略
      final proxy = await _readWindowsSystemProxy();
      if (proxy != null) {
        hc.findProxy = (_) => proxy;
      }
    }
    hc.connectionTimeout = _connectTimeout;
    // IOClient 从 package:http/io_client.dart 导出（http.dart 主库不含）
    return IOClient(hc);
  }

  /// API 配额耗尽/被拒时的兜底：用 github.com 的 releases/latest 302 跳转拿版本号。
  /// 成功返回降级结果（无更新说明与安装包信息），任何失败都返回 null 交回调用方报原错误。
  Future<UpdateCheckResult?> _checkViaRedirect() async {
    String? location;
    try {
      location = await _requestLocation();
    } catch (_) {
      return null; // 兜底失败不掩盖 API 的原始错误
    }
    if (location == null) return null;
    // Location 形如 https://github.com/<owner>/<repo>/releases/tag/v0.2.2
    final segments = Uri.tryParse(location)?.pathSegments;
    if (segments == null || segments.length < 2) return null;
    if (segments[segments.length - 2] != 'tag') return null;
    final tag = segments.last;
    final latestVersion = tag.replaceFirst(RegExp(r'^[vV]'), '');
    // 与主路径一致：非纯数字语义版本不做比较，避免误报
    if (_parseVersion(latestVersion) == null ||
        _parseVersion(currentVersion) == null) {
      return null;
    }
    return UpdateCheckResult(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      releaseName: tag,
      releaseUrl: location,
      targetPlatform: targetPlatform,
      updateAvailable: _isNewerVersion(latestVersion, currentVersion),
    );
  }

  /// 统一分派 302 兜底请求，保证兜底逻辑本身也可测试。
  Future<String?> _requestLocation() {
    final fetcher = _locationFetcher;
    if (fetcher != null) return fetcher();
    return _fetchLatestTagLocation();
  }

  /// 读取 releases/latest 的 302 Location 响应头。先走系统代理，失败再直连。
  Future<String?> _fetchLatestTagLocation() async {
    for (final useSystemProxy in [true, false]) {
      final client = await _buildClient(useSystemProxy: useSystemProxy);
      try {
        // 必须禁止自动跟随重定向，否则拿不到 Location 头
        final request = http.Request('GET', Uri.parse(AppInfo.releasePageUrl))
          ..followRedirects = false
          ..headers['User-Agent'] = _userAgent;
        final response = await client.send(request).timeout(_readTimeout);
        // 释放响应体连接，避免占用 socket
        await response.stream.drain<void>();
        final location = response.headers['location'];
        if (location != null && location.isNotEmpty) return location;
      } catch (_) {
        // 本轮失败继续尝试下一种代理策略
      } finally {
        client.close();
      }
    }
    return null;
  }

  /// 读取 Windows 系统代理（注册表 Internet Settings），
  /// 返回 dart HttpClient findProxy 所需的 "PROXY host:port" 字符串；未启用返回 null。
  static Future<String?> _readWindowsSystemProxy() async {
    if (!Platform.isWindows) return null;
    try {
      final key = CURRENT_USER.open(
        r'Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      );
      final enabled = key.getInt('ProxyEnable') ?? 0;
      final server = key.getString('ProxyServer') ?? '';
      if (enabled != 1 || server.trim().isEmpty) return null;
      final hostPort = _extractHttpsProxy(server.trim()) ?? server.trim();
      return 'PROXY $hostPort';
    } catch (_) {
      // 注册表读取失败（权限/键缺失等）视为未配置代理，走默认策略
      return null;
    }
  }

  /// ProxyServer 可能是 "host:port" 或 "http=host:port;https=host:port" 的复合格式，
  /// 提取 https 段（GitHub API 为 HTTPS 请求）。
  static String? _extractHttpsProxy(String server) {
    if (!server.contains('=')) return null;
    for (final part in server.split(';')) {
      final kv = part.split('=');
      if (kv.length == 2 && kv[0].trim().toLowerCase() == 'https') {
        return kv[1].trim();
      }
    }
    return null;
  }

  /// 保守语义版本比较：latest > current 返回 true。
  /// 任一版本含非数字段（如预发布标签）时返回 false，避免误报更新。
  static bool _isNewerVersion(String latest, String current) {
    final l = _parseVersion(latest);
    final c = _parseVersion(current);
    if (l == null || c == null) return false;
    final len = l.length > c.length ? l.length : c.length;
    while (l.length < len) {
      l.add(0);
    }
    while (c.length < len) {
      c.add(0);
    }
    for (var i = 0; i < len; i++) {
      if (l[i] != c[i]) return l[i] > c[i];
    }
    return false;
  }

  static List<int>? _parseVersion(String version) {
    final parts = version.trim().split('.');
    if (parts.isEmpty) return null;
    final nums = <int>[];
    for (final part in parts) {
      final n = int.tryParse(part);
      if (n == null) return null; // 非数字段视为非法版本，不提示更新
      nums.add(n);
    }
    return nums;
  }

  /// 从 Release assets 中挑选当前平台的安装包（名称、直链、大小）。
  /// 同扩展名有多个候选时，优先带 setup/installer 字样的那个。
  _InstallerAssetInfo? _pickInstallerAsset(dynamic assets) {
    if (assets is! List) return null;
    final extension = targetPlatform.installerExtension;
    if (extension == null) return null;
    _InstallerAssetInfo? fallback;
    for (final asset in assets) {
      if (asset is! Map || asset['name'] is! String) continue;
      final assetName = asset['name'] as String;
      final name = assetName.toLowerCase();
      if (!name.endsWith(extension)) continue;
      final info = _InstallerAssetInfo(
        name: assetName,
        downloadUrl: asset['browser_download_url'] as String? ?? '',
        size: asset['size'] is int ? asset['size'] as int : null,
      );
      fallback ??= info;
      if (name.contains('setup') || name.contains('installer')) return info;
    }
    return fallback;
  }

  /// 下载安装包到 [savePath]。[onProgress] 收到已下载字节数与总字节数
  /// （总数未知时为 null）。[isCancelled] 返回 true 时中止下载并清掉半成品。
  ///
  /// 代理策略与检查更新一致：先走系统代理，网络失败回退直连重试一次——
  /// GitHub 的 release asset 走 objects.githubusercontent.com，
  /// 国内网络常出现 API 能通但下载超时的情况。
  Future<String> downloadInstaller({
    required String downloadUrl,
    required String savePath,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    try {
      return await _download(
        downloadUrl: downloadUrl,
        savePath: savePath,
        useSystemProxy: true,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    } on UpdateDownloadException catch (e) {
      // 取消与服务端明确报错不必换代理重试，只有连接层失败才值得回退直连
      if (e.code != 'network') rethrow;
      return _download(
        downloadUrl: downloadUrl,
        savePath: savePath,
        useSystemProxy: false,
        onProgress: onProgress,
        isCancelled: isCancelled,
      );
    }
  }

  Future<String> _download({
    required String downloadUrl,
    required String savePath,
    required bool useSystemProxy,
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final client = await _buildClient(useSystemProxy: useSystemProxy);
    final file = File(savePath);
    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(downloadUrl))
        ..followRedirects = true
        ..headers['User-Agent'] = _userAgent;
      final response = await client.send(request).timeout(_connectTimeout);
      if (response.statusCode != 200) {
        // 释放连接，否则 socket 会被挂住直到超时
        await response.stream.drain<void>();
        throw UpdateDownloadException('http_status', '${response.statusCode}');
      }
      final total = response.contentLength;
      var received = 0;
      sink = file.openWrite();
      await for (final chunk in response.stream) {
        if (isCancelled?.call() ?? false) {
          throw const UpdateDownloadException('cancelled');
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      // 长度校验能挡住中途断流写出的残包，避免把坏包交给安装器
      if (total != null && await file.length() != total) {
        throw const UpdateDownloadException('io', 'incomplete');
      }
      return savePath;
    } on UpdateDownloadException {
      await _discardPartialFile(sink, file);
      rethrow;
    } on FileSystemException catch (e) {
      await _discardPartialFile(sink, file);
      throw UpdateDownloadException('io', e.message);
    } catch (e) {
      await _discardPartialFile(sink, file);
      throw UpdateDownloadException('network', e.toString());
    } finally {
      client.close();
    }
  }

  /// 失败时清掉半成品，避免下次误把残包当成可用安装器。
  static Future<void> _discardPartialFile(IOSink? sink, File file) async {
    try {
      await sink?.close();
    } catch (_) {
      // 关闭失败不影响删除，继续清理
    }
    try {
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // 删不掉（占用等）也不应覆盖真正的下载错误
    }
  }

  /// 启动已下载的安装包。Windows 直接以管理员权限拉起 NSIS 安装器；
  /// Android 通过平台通道交给系统包安装器（需用户授权“安装未知应用”）。
  /// 抛出 [UpdateInstallException] 表示无法进入安装流程。
  Future<void> launchInstaller(String installerPath) async {
    if (!File(installerPath).existsSync()) {
      throw const UpdateInstallException('missing_file');
    }
    if (Platform.isWindows) {
      return _launchWindowsInstaller(installerPath);
    }
    if (Platform.isAndroid) {
      return _launchAndroidInstaller(installerPath);
    }
    throw const UpdateInstallException('unsupported_platform');
  }

  /// Windows：NSIS 安装器声明了 requestExecutionLevel admin，
  /// 必须经 ShellExecute 的 runas 动词触发 UAC，直接 Process.start 会被拒。
  /// 安装器自身会先关闭正在运行的旧进程，所以这里不需要自杀。
  Future<void> _launchWindowsInstaller(String installerPath) async {
    // 单引号包裹 -FilePath 并转义内部单引号，避免路径含空格或引号时被拆解
    final quoted = installerPath.replaceAll("'", "''");
    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "Start-Process -FilePath '$quoted' -Verb RunAs",
      ],
    );
    // 用户在 UAC 弹窗点“否”时 PowerShell 返回非 0，需要如实反馈而不是假装已启动
    if (result.exitCode != 0) {
      throw UpdateInstallException(
        'launch_failed',
        '${result.stderr}'.trim(),
      );
    }
  }

  /// Android：APK 必须通过 FileProvider 的 content:// URI 交给系统安装器，
  /// 原生侧还要检查 REQUEST_INSTALL_PACKAGES 授权状态。
  Future<void> _launchAndroidInstaller(String installerPath) async {
    try {
      await _platform.invokeMethod<void>('installApk', {'path': installerPath});
    } on PlatformException catch (e) {
      throw UpdateInstallException(e.code, e.message ?? '');
    } on MissingPluginException {
      throw const UpdateInstallException('unsupported_platform');
    }
  }

  /// 下载目录：优先系统临时目录，安装包属于用完即弃的中间产物。
  /// Android 侧必须落在 FileProvider 已声明的 cache 路径下才能被系统安装器读取。
  static Future<String> resolveDownloadPath(String fileName) async {
    final dir = await getTemporaryDirectory();
    final target = Directory(p.join(dir.path, 'updates'));
    if (!target.existsSync()) {
      await target.create(recursive: true);
    }
    return p.join(target.path, fileName);
  }
}

/// Release Asset 的结构化信息，供下载时使用直链和展示文件大小。
class _InstallerAssetInfo {
  final String name;
  final String downloadUrl;
  final int? size;
  const _InstallerAssetInfo({
    required this.name,
    required this.downloadUrl,
    this.size,
  });
}
