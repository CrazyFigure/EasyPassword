/// 更新检测服务：查询 GitHub 最新 Release 并做语义版本比较。
///
/// 代理处理策略对齐 MyTerminal（参考其 commands.rs 的 check_for_updates）：
/// 1. 首次请求走系统代理（Windows 读取注册表代理；其他平台默认走环境变量策略）；
/// 2. 网络错误（代理不可达等）→ 回退直连重试一次；
/// 3. 403（代理节点数据中心 IP 常被 GitHub API 风控）→ 回退直连重试一次；
/// 4. 403 需区分：响应头 X-RateLimit-Remaining 为 0 才确认是 API 配额耗尽，
///    否则多为代理/安全策略拦截，不应误报成限流；
/// 5. 版本比较只做保守语义比较：tag 含非数字段时视为无更新，避免误报。
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:win32_registry/win32_registry.dart';

import '../core/constants.dart';

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

  const UpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseName,
    required this.releaseUrl,
    required this.updateAvailable,
    this.publishedAt,
    this.releaseBody,
    this.installerAssetName,
  });
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

class UpdateService {
  /// 连接超时（对齐 MyTerminal UPDATE_HTTP_CONNECT_TIMEOUT 量级）
  static const _connectTimeout = Duration(seconds: 10);

  /// 读取超时（对齐 MyTerminal UPDATE_HTTP_READ_TIMEOUT = 40s）
  static const _readTimeout = Duration(seconds: 40);

  static const _userAgent = 'EasyPassword';

  /// 检测是否有新版本。失败时抛出 [UpdateCheckException]。
  Future<UpdateCheckResult> check() async {
    http.Response response;
    // 首次走系统代理；网络错误（代理不可达等）回退直连重试一次
    try {
      response = await _fetch(useSystemProxy: true);
    } catch (_) {
      response = await _fetch(useSystemProxy: false);
    }
    // 403：代理节点被 GitHub API 风控 → 直连重试一次
    if (response.statusCode == 403) {
      response = await _fetch(useSystemProxy: false);
    }
    if (response.statusCode == 403) {
      // 区分限流与拦截：X-RateLimit-Remaining 为 0 才确认为配额耗尽
      final remaining = int.tryParse(
              response.headers['x-ratelimit-remaining'] ?? '') ??
          -1;
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
      final latestVersion =
          latestTag.replaceFirst(RegExp(r'^[vV]'), '');
      final htmlUrl = data['html_url'] as String? ?? '';
      return UpdateCheckResult(
        currentVersion: AppInfo.currentVersion,
        latestVersion: latestVersion,
        releaseName: data['name'] as String? ?? latestTag,
        releaseUrl:
            htmlUrl.isNotEmpty ? htmlUrl : AppInfo.releasePageUrl,
        publishedAt: data['published_at'] as String?,
        releaseBody: data['body'] as String?,
        installerAssetName: _pickInstallerAsset(data['assets']),
        updateAvailable: _isNewerVersion(
            latestVersion, AppInfo.currentVersion),
      );
    } on UpdateCheckException {
      rethrow;
    } catch (e) {
      throw UpdateCheckException('parse', e.toString());
    }
  }

  /// 发起请求。[useSystemProxy] 为 true 时优先使用 Windows 系统代理；
  /// false 时强制直连（no_proxy 语义）。
  Future<http.Response> _fetch({required bool useSystemProxy}) async {
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
    final client = IOClient(hc);
    try {
      // GitHub API 要求明确 User-Agent
      return await client
          .get(
            Uri.parse(AppInfo.releaseApiUrl),
            headers: {'User-Agent': _userAgent},
          )
          .timeout(_readTimeout);
    } finally {
      client.close();
    }
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

  /// 从 Release assets 中挑选 Windows 安装包文件名（仅用于展示，不自动下载）。
  static String? _pickInstallerAsset(dynamic assets) {
    if (assets is! List) return null;
    String? fallback;
    for (final asset in assets) {
      if (asset is! Map || asset['name'] is! String) continue;
      final name = (asset['name'] as String).toLowerCase();
      if (!name.endsWith('.exe')) continue;
      fallback ??= asset['name'] as String;
      if (name.contains('setup') || name.contains('installer')) {
        return asset['name'] as String;
      }
    }
    return fallback;
  }
}
