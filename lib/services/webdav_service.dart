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

  /// 拉取远端快照；不存在返回 null
  Future<String?> pullSnapshot(
      String baseUrl, String username, String password) async {
    final uri = _resolveUri(baseUrl, _snapshotName);
    final resp = await http.get(uri, headers: _authHeaders(username, password));
    if (resp.statusCode == 404 || resp.statusCode == 405) return null;
    if (resp.statusCode != 200) {
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
      throw Exception('WebDAV 推送失败: HTTP ${resp.statusCode}');
    }
  }

  Future<void> _ensureCollection(
      String baseUrl, String username, String password) async {
    final uri = _resolveUri(baseUrl, '');
    // 尝试建目录；已存在时 405 忽略
    final client = http.Client();
    try {
      final req = http.Request('MKCOL', uri);
      req.headers.addAll(_authHeaders(username, password));
      await client.send(req);
    } finally {
      client.close();
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
