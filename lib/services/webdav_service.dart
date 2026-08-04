/// WebDAV 同步服务：加密快照 + 增量合并
/// 原则：先落本地，再推送远端（需求 4 / 4.1）
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import 'crypto_service.dart';
import 'data_service.dart';
import 'database.dart';

class WebDavService {
  final CryptoService crypto;
  final DataService data;

  WebDavService(this.crypto, this.data);

  static const String _snapshotName = 'easypassword-snapshot.json.enc';

  // ================= 导出 =================

  /// 导出当前全部数据为 JSON（敏感字段仍为密文）
  Future<Map<String, dynamic>> exportAll() async {
    final items = <Map<String, dynamic>>[];
    for (final type in const ['password', 'apikey']) {
      final list = await data.listItems(type);
      for (final item in list) {
        final accounts = await data.listAccounts(item.id);
        final accList = <Map<String, dynamic>>[];
        for (final acc in accounts) {
          final keys = await data.listApiKeys(acc.id);
          accList.add({
            ...acc.toMap(),
            'api_keys': keys.map((k) => k.toMap()).toList(),
          });
        }
        items.add({
          ...item.toMap(),
          'accounts': accList,
        });
      }
    }
    // 全局修订号：当前时间戳（单调递增）
    final revision = DateTime.now().millisecondsSinceEpoch.toString();
    await DatabaseService.setSetting('sync_revision', revision);
    return {
      'revision': revision,
      'app': 'EasyPassword',
      'version': 1,
      'items': items,
    };
  }

  /// 生成加密快照文本
  Future<String> buildSnapshot() async {
    final payload = jsonEncode(await exportAll());
    return crypto.encrypt(payload);
  }

  // ================= 导入合并 =================

  /// 解析并合并远端快照（增量：以 updated_at 晚者胜）
  Future<int> mergeSnapshot(String encryptedSnapshot) async {
    final jsonStr = await crypto.decrypt(encryptedSnapshot);
    final remote = jsonDecode(jsonStr) as Map<String, dynamic>;
    final remoteItems = (remote['items'] as List?) ?? [];

    var merged = 0;
    final db = await DatabaseService.db;
    await db.transaction((txn) async {
      for (final raw in remoteItems) {
        final item = Map<String, dynamic>.from(raw as Map);
        final itemId = item['id'] as String;
        final local = await _queryLocalItem(txn, itemId);

        // 条目级合并
        if (local == null || (item['updated_at'] as int) > (local['updated_at'] as int)) {
          final accounts = (item.remove('accounts') as List?) ?? [];
          await txn.insert(
            'password_items',
            item,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          // 远端账号整体覆盖该条目的账号
          await txn.delete('accounts', where: 'item_id = ?', whereArgs: [itemId]);
          await txn.delete('api_keys',
              where: 'account_id IN (SELECT id FROM accounts WHERE item_id = ?)',
              whereArgs: [itemId]);
          for (final a in accounts) {
            final acc = Map<String, dynamic>.from(a as Map);
            final keys = (acc.remove('api_keys') as List?) ?? [];
            await txn.insert('accounts', acc,
                conflictAlgorithm: ConflictAlgorithm.replace);
            for (final k in keys) {
              await txn.insert('api_keys', Map<String, dynamic>.from(k as Map),
                  conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
          merged++;
        }
      }
    });
    // 合并后记录远端修订号
    final rev = remote['revision']?.toString();
    if (rev != null) {
      await DatabaseService.setSetting('sync_revision', rev);
    }
    return merged;
  }

  Future<Map<String, dynamic>?> _queryLocalItem(
      DatabaseExecutor txn, String id) async {
    final rows = await txn.query('password_items',
        where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first;
  }

  // ================= WebDAV 传输 =================

  /// 测试连接：PROPFIND 根目录，验证地址可达性与凭据
  Future<void> testConnection(
      String baseUrl, String username, String password) async {
    final uri = _resolveUri(baseUrl, '');
    final client = http.Client();
    try {
      final req = http.Request('PROPFIND', uri);
      req.headers.addAll({
        ..._authHeaders(username, password),
        'Depth': '0',
      });
      final resp = await client.send(req);
      await resp.stream.drain();
      final status = resp.statusCode;
      // 200 或 207 Multi-Status 均为标准成功响应
      if (status == 200 || status == 207) return;
      if (status == 401 || status == 403) throw Exception(_authError(status));
      throw Exception('连接失败（HTTP $status）：请检查服务器地址是否正确');
    } finally {
      client.close();
    }
  }

  /// 拉取远端快照；不存在返回 null
  Future<String?> pullSnapshot(
      String baseUrl, String username, String password) async {
    final uri = _resolveUri(baseUrl, _snapshotName);
    final resp = await http.get(uri, headers: _authHeaders(username, password));
    if (resp.statusCode == 404 || resp.statusCode == 405) return null;
    if (resp.statusCode != 200) {
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw Exception(_authError(resp.statusCode));
      }
      throw Exception('WebDAV 拉取失败: HTTP ${resp.statusCode}');
    }
    return resp.body;
  }

  /// 推送加密快照（覆盖写，先落本地再推送的最后一环）
  Future<void> pushSnapshot(
      String baseUrl, String username, String password, String encrypted) async {
    // 确保目录存在
    await _ensureCollection(baseUrl, username, password);
    final uri = _resolveUri(baseUrl, _snapshotName);
    final resp = await http.put(
      uri,
      headers: {
        ..._authHeaders(username, password),
        'Content-Type': 'application/octet-stream',
      },
      body: encrypted,
    );
    if (resp.statusCode >= 300) {
      throw Exception(_pushError(resp.statusCode));
    }
  }

  /// 确保远端目录存在：先 PROPFIND 检查每一级是否已存在，
  /// 已存在则跳过 MKCOL（治本：坚果云对已存在路径 MKCOL 仍返 403，
  /// 用户按提示在网页端建好子目录后，不应再触发写入操作）。
  Future<void> _ensureCollection(
      String baseUrl, String username, String password) async {
    final uri = _resolveUri(baseUrl, '');
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    for (var i = 1; i <= segments.length; i++) {
      final dirUri = uri.replace(pathSegments: segments.take(i).toList());
      // 先探测目录是否存在；存在则直接跳过
      if (await _directoryExists(dirUri, username, password)) {
        continue;
      }
      // 不存在再尝试 MKCOL 创建
      final status = await _mkcol(dirUri, username, password);
      // 401 才是认证失败；403 在坚果云上通常是"操作被拒"
      if (status == 401) {
        throw Exception(_authError(status));
      }
      if (status == 403) {
        throw Exception(_writeForbiddenError(status));
      }
      // 2xx 创建成功；3xx/405 已存在；其余视为无法创建
      final ok = (status >= 200 && status < 400) || status == 405;
      if (!ok) {
        throw Exception(
            'WebDAV 目录创建失败（HTTP $status）：请检查服务器地址是否正确'
            '（坚果云形如 https://dav.jianguoyun.com/dav/），'
            '或先在服务端手动创建该目录');
      }
    }
  }

  /// 用 PROPFIND depth=0 探测目录是否存在：坚果云等标准 WebDAV 对已存在目录
  /// 返回 207 Multi-Status，对不存在返回 404，对认证失败返回 401。
  Future<bool> _directoryExists(
      Uri uri, String username, String password) async {
    final client = http.Client();
    try {
      final req = http.Request('PROPFIND', uri);
      req.headers.addAll({
        ..._authHeaders(username, password),
        'Depth': '0',
      });
      final resp = await client.send(req);
      await resp.stream.drain();
      final s = resp.statusCode;
      return s == 200 || s == 207;
    } finally {
      client.close();
    }
  }

  Future<int> _mkcol(Uri uri, String username, String password) async {
    final client = http.Client();
    try {
      final req = http.Request('MKCOL', uri);
      req.headers.addAll(_authHeaders(username, password));
      final resp = await client.send(req);
      await resp.stream.drain();
      return resp.statusCode;
    } finally {
      client.close();
    }
  }

  String _authError(int status) =>
      'WebDAV 认证失败（HTTP $status）：请检查用户名与密码，坚果云需使用「应用密码」';

  /// 写操作被拒（403）：与认证失败不同——PROPFIND 通过说明凭据有效，
  /// 403 通常是路径不允许写入（如坚果云根目录 /dav/ 下需手动建子目录）
  /// 或应用密码未授予写权限。
  String _writeForbiddenError(int status) =>
      'WebDAV 操作被拒（HTTP $status）：服务器拒绝了写入操作。'
      '请检查：'
      '① WebDAV 路径下是否需要先手动建立子目录（坚果云需在 dav.jianguoyun.com/dav/ '
      '下手动新建子文件夹，并把"服务器地址"填为 https://dav.jianguoyun.com/dav/<子目录>/）；'
      '② 应用密码是否已授予写入权限（坚果云应用密码生成时可勾选权限）';

  String _pushError(int status) {
    switch (status) {
      case 401:
        return _authError(status);
      case 403:
        return _writeForbiddenError(status);
      case 404:
        return 'WebDAV 推送失败（HTTP 404）：远端目录不存在或服务器地址有误，'
            '请确认地址包含正确的 WebDAV 路径'
            '（坚果云形如 https://dav.jianguoyun.com/dav/），'
            '或在服务端手动创建该目录';
      case 409:
        return 'WebDAV 推送失败（HTTP 409）：远端目录不存在，无法写入快照文件';
      default:
        return 'WebDAV 推送失败: HTTP $status';
    }
  }

  Map<String, String> _authHeaders(String username, String password) {
    return {
      'Authorization':
          'Basic ${base64Encode(utf8.encode('$username:$password'))}',
    };
  }

  Uri _resolveUri(String baseUrl, String fileName) {
    var base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse('$base$fileName');
  }

  /// 一键同步：拉取 → 合并落本地 → 推送（需求 4.1）
  Future<SyncSummary> syncAll(String baseUrl, String username, String password) async {
    final remote = await pullSnapshot(baseUrl, username, password);
    var merged = 0;
    if (remote != null) {
      merged = await mergeSnapshot(remote);
    }
    // 先落本地已完成（merge 写库），再推送
    final snapshot = await buildSnapshot();
    await pushSnapshot(baseUrl, username, password, snapshot);
    return SyncSummary(merged: merged, pushed: true);
  }
}

class SyncSummary {
  final int merged;
  final bool pushed;
  const SyncSummary({required this.merged, required this.pushed});
}
