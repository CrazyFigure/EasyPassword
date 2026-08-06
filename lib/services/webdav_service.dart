/// WebDAV 多端同步服务：跨设备加密快照、删除墓碑与逐行最后修改者胜。
/// 自动同步始终先合并本地与远端，再用条件写入防止并发设备互相覆盖。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import 'crypto_service.dart';
import 'data_service.dart';
import 'database.dart';

/// 用户可选择的三种同步方向。
enum WebDavSyncMode { localToRemote, remoteToLocal, automatic }

class WebDavService {
  final CryptoService crypto;
  final DataService data;

  WebDavService(this.crypto, this.data);

  static const String _snapshotName = 'easypassword-snapshot.json.enc';
  static const String _collectionName = 'EasyPassword';
  static const int _snapshotVersion = 3;

  // ================= 快照导出与加密 =================

  /// 导出完整同步状态。业务表直接读取全部行，因此软删除墓碑也会进入快照，
  /// 断网设备恢复后才能用 updated_at 正确处理“修改与删除”的冲突。
  Future<Map<String, dynamic>> exportAll() async {
    final db = await DatabaseService.db;
    final folders = await db.query('folders');
    final items = await db.query('password_items');
    final accounts = <Map<String, dynamic>>[];
    final apiKeys = <Map<String, dynamic>>[];

    // 整个 JSON 随后会再用 WebDAV 共享密钥加密，因此跨设备快照内部使用
    // 明文逻辑值；导入另一台设备时再用该设备自己的数据密钥重新加密。
    for (final row in await db.query('accounts')) {
      final account = Map<String, dynamic>.from(row);
      final encrypted = (account.remove('password_enc') as String?) ?? '';
      account['password_plain'] = await crypto.decrypt(encrypted);
      accounts.add(account);
    }
    for (final row in await db.query('api_keys')) {
      final apiKey = Map<String, dynamic>.from(row);
      final encrypted = (apiKey.remove('key_enc') as String?) ?? '';
      apiKey['key_plain'] = await crypto.decrypt(encrypted);
      apiKeys.add(apiKey);
    }

    final revision = DateTime.now().millisecondsSinceEpoch.toString();
    await DatabaseService.setSetting('sync_revision', revision);
    return {
      'app': 'EasyPassword',
      'version': _snapshotVersion,
      'revision': revision,
      'folders': folders.map(Map<String, dynamic>.from).toList(),
      'items': items.map(Map<String, dynamic>.from).toList(),
      'accounts': accounts,
      'api_keys': apiKeys,
      'settings': await DatabaseService.getSyncableSettingRows(),
    };
  }

  /// 生成快照。网络同步传入连接信息后使用跨设备共享密钥；未传时沿用
  /// 本机字段密钥，保留本地单元测试和旧备份调用的兼容性。
  Future<String> buildSnapshot({
    String? baseUrl,
    String username = '',
    String password = '',
  }) async {
    final payload = jsonEncode(await exportAll());
    if (baseUrl == null) return crypto.encrypt(payload);
    return crypto.encryptForSync(
      payload,
      _syncSecret(username, password),
      _syncIdentity(baseUrl),
    );
  }

  // ================= 快照导入、覆盖与合并 =================

  /// 合并快照：同一主键逐行比较 updated_at，时间更新的一侧胜出；
  /// 时间完全相同时再比较规范化内容，确保所有设备最终选择同一结果。
  /// 返回合并的顶层条目数，维持旧版调用约定。
  Future<int> mergeSnapshot(
    String encryptedSnapshot, {
    String? baseUrl,
    String username = '',
    String password = '',
  }) async {
    final snapshot = await _decodeSnapshot(
      encryptedSnapshot,
      baseUrl: baseUrl,
      username: username,
      password: password,
    );
    return _applySnapshot(snapshot, replaceLocal: false);
  }

  /// 远端覆盖本地：完整替换四张业务表和可同步系统设置。
  /// WebDAV 凭据、设备数据密钥及同步运行状态始终保留在本机。
  Future<int> replaceLocalSnapshot(
    String encryptedSnapshot, {
    required String baseUrl,
    String username = '',
    String password = '',
  }) async {
    final snapshot = await _decodeSnapshot(
      encryptedSnapshot,
      baseUrl: baseUrl,
      username: username,
      password: password,
    );
    return _applySnapshot(snapshot, replaceLocal: true);
  }

  /// 解密并校验快照基本结构，错误凭据和损坏内容都给出可操作提示。
  Future<Map<String, dynamic>> _decodeSnapshot(
    String encryptedSnapshot, {
    String? baseUrl,
    required String username,
    required String password,
  }) async {
    final jsonText = baseUrl == null
        ? await crypto.decrypt(encryptedSnapshot)
        : await crypto.decryptForSync(
            encryptedSnapshot,
            _syncSecret(username, password),
            _syncIdentity(baseUrl),
          );
    try {
      final value = jsonDecode(jsonText);
      if (value is! Map) throw const FormatException();
      final snapshot = Map<String, dynamic>.from(value);
      if (snapshot['app'] != 'EasyPassword') throw const FormatException();
      return snapshot;
    } catch (_) {
      throw Exception('同步快照格式无效或已经损坏');
    }
  }

  /// 应用解密后的快照。v3 为四表扁平结构；v1/v2 的嵌套结构会在此
  /// 展开后继续合并，保证已有远端文件可以平滑升级。
  Future<int> _applySnapshot(Map<String, dynamic> snapshot,
      {required bool replaceLocal}) async {
    final rows = _extractRows(snapshot);
    final db = await DatabaseService.db;
    var mergedItems = 0;

    await db.transaction((txn) async {
      if (replaceLocal) {
        // 先删子表再删父表，兼容未来补充外键约束的数据库版本。
        for (final table in const [
          'api_keys',
          'accounts',
          'password_items',
          'folders',
        ]) {
          await txn.delete(table);
        }
        final placeholders =
            List.filled(DatabaseService.syncableSettingKeys.length, '?')
                .join(',');
        await txn.delete(
          'settings',
          where: 'key IN ($placeholders)',
          whereArgs: DatabaseService.syncableSettingKeys.toList(),
        );
      }

      for (final table in const [
        'folders',
        'password_items',
        'accounts',
        'api_keys',
      ]) {
        for (final remoteRow in rows[table]!) {
          final id = remoteRow['id']?.toString();
          if (id == null || id.isEmpty) continue;
          final local =
              replaceLocal ? null : await _queryLocalRow(txn, table, 'id', id);
          if (replaceLocal ||
              local == null ||
              await _remoteWins(table, remoteRow, local)) {
            final prepared = await _prepareForLocal(table, remoteRow);
            await txn.insert(
              table,
              prepared,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            if (table == 'password_items') mergedItems++;
          }
        }
      }

      for (final remoteSetting in rows['settings']!) {
        final key = remoteSetting['key']?.toString();
        if (key == null || !DatabaseService.syncableSettingKeys.contains(key)) {
          continue;
        }
        final local = replaceLocal
            ? null
            : await _queryLocalRow(txn, 'settings', 'key', key);
        if (replaceLocal ||
            local == null ||
            await _remoteWins('settings', remoteSetting, local)) {
          await txn.insert(
            'settings',
            {
              'key': key,
              'value': remoteSetting['value']?.toString() ?? '',
              'updated_at': _timestampOf(remoteSetting),
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    });

    final revision = snapshot['revision']?.toString();
    if (revision != null) {
      await DatabaseService.setSetting('sync_revision', revision);
    }
    return mergedItems;
  }

  /// 把 v1/v2 条目中的 accounts/api_keys 展开为 v3 的独立行集合。
  Map<String, List<Map<String, dynamic>>> _extractRows(
      Map<String, dynamic> snapshot) {
    final result = <String, List<Map<String, dynamic>>>{
      'folders': _mapRows(snapshot['folders']),
      'password_items': <Map<String, dynamic>>[],
      'accounts': _mapRows(snapshot['accounts']),
      'api_keys': _mapRows(snapshot['api_keys']),
      'settings': _mapRows(snapshot['settings']),
    };
    for (final rawItem in _mapRows(snapshot['items'])) {
      final item = Map<String, dynamic>.from(rawItem);
      final nestedAccounts = _mapRows(item.remove('accounts'));
      result['password_items']!.add(item);
      for (final rawAccount in nestedAccounts) {
        final account = Map<String, dynamic>.from(rawAccount);
        result['api_keys']!.addAll(_mapRows(account.remove('api_keys')));
        result['accounts']!.add(account);
      }
    }
    return result;
  }

  List<Map<String, dynamic>> _mapRows(Object? value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return [
      for (final row in value)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }

  /// 跨设备导入时把快照中的逻辑明文重新加密为本机字段密文。
  Future<Map<String, dynamic>> _prepareForLocal(
      String table, Map<String, dynamic> remoteRow) async {
    final row = Map<String, dynamic>.from(remoteRow);
    if (table == 'accounts' && row.containsKey('password_plain')) {
      final plain = row.remove('password_plain')?.toString() ?? '';
      row['password_enc'] = await crypto.encrypt(plain);
    } else if (table == 'api_keys' && row.containsKey('key_plain')) {
      final plain = row.remove('key_plain')?.toString() ?? '';
      row['key_enc'] = await crypto.encrypt(plain);
    }
    return row;
  }

  Future<Map<String, dynamic>?> _queryLocalRow(
      DatabaseExecutor txn, String table, String keyColumn, String id) async {
    final rows = await txn.query(
      table,
      where: '$keyColumn = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// 主要按毫秒时间比较；时间相同则比较去除本机密文差异后的规范 JSON，
  /// 避免两台设备在同一毫秒修改时来回覆盖、无法收敛。
  Future<bool> _remoteWins(String table, Map<String, dynamic> remote,
      Map<String, dynamic> local) async {
    final remoteTime = _timestampOf(remote);
    final localTime = _timestampOf(local);
    if (remoteTime != localTime) return remoteTime > localTime;
    final remoteLogical = Map<String, dynamic>.from(remote);
    final localLogical = Map<String, dynamic>.from(local);
    if (table == 'accounts') {
      if (!remoteLogical.containsKey('password_plain')) {
        remoteLogical['password_plain'] = await crypto
            .decrypt(remoteLogical.remove('password_enc')?.toString() ?? '');
      }
      localLogical['password_plain'] = await crypto
          .decrypt(localLogical.remove('password_enc')?.toString() ?? '');
    } else if (table == 'api_keys') {
      if (!remoteLogical.containsKey('key_plain')) {
        remoteLogical['key_plain'] = await crypto
            .decrypt(remoteLogical.remove('key_enc')?.toString() ?? '');
      }
      localLogical['key_plain'] = await crypto
          .decrypt(localLogical.remove('key_enc')?.toString() ?? '');
    }
    return _canonicalJson(remoteLogical)
            .compareTo(_canonicalJson(localLogical)) >
        0;
  }

  int _timestampOf(Map<String, dynamic> row) {
    final value = row['updated_at'];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _canonicalJson(Map<String, dynamic> value) {
    final sorted = <String, dynamic>{};
    for (final key in value.keys.toList()..sort()) {
      sorted[key] = value[key];
    }
    return jsonEncode(sorted);
  }

  // ================= WebDAV 目录与传输 =================

  /// 测试连接同时验证写权限；应用会在用户填写的 WebDAV 根地址下自动创建
  /// EasyPassword 文件夹，不再要求用户提前进入网页端手工建目录。
  Future<void> testConnection(
      String baseUrl, String username, String password) async {
    await _ensureCollection(baseUrl, username, password);
  }

  /// 拉取远端快照；文件尚不存在时返回 null。
  Future<String?> pullSnapshot(
      String baseUrl, String username, String password) async {
    return (await _pullRemote(baseUrl, username, password)).body;
  }

  /// 无条件推送快照，供明确选择“本地覆盖远端”的操作使用。
  Future<void> pushSnapshot(String baseUrl, String username, String password,
      String encrypted) async {
    await _putRemote(baseUrl, username, password, encrypted);
  }

  Future<_RemoteSnapshot> _pullRemote(
      String baseUrl, String username, String password) async {
    await _ensureCollection(baseUrl, username, password);
    final uri = _resolveFileUri(baseUrl, _snapshotName);
    final response =
        await http.get(uri, headers: _authHeaders(username, password));
    if (response.statusCode == 404) {
      return const _RemoteSnapshot(body: null, etag: null);
    }
    if (response.statusCode != 200) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw Exception(_authError(response.statusCode));
      }
      throw Exception('WebDAV 拉取失败（HTTP ${response.statusCode}）');
    }
    return _RemoteSnapshot(
      body: response.body,
      etag: response.headers['etag'],
    );
  }

  /// 条件 PUT 用 ETag 保护“拉取—合并—推送”窗口；若其他设备抢先写入，
  /// 调用方会重新拉取合并，而不是覆盖掉对方刚上传的数据。
  Future<void> _putRemote(
    String baseUrl,
    String username,
    String password,
    String encrypted, {
    String? expectedEtag,
    bool onlyIfMissing = false,
  }) async {
    await _ensureCollection(baseUrl, username, password);
    final headers = <String, String>{
      ..._authHeaders(username, password),
      'Content-Type': 'application/octet-stream',
      if (expectedEtag != null) 'If-Match': expectedEtag,
      if (onlyIfMissing) 'If-None-Match': '*',
    };
    final response = await http.put(
      _resolveFileUri(baseUrl, _snapshotName),
      headers: headers,
      body: encrypted,
    );
    if (response.statusCode == 412) throw const _RemoteChangedException();
    if (response.statusCode >= 300) {
      throw Exception(_pushError(response.statusCode));
    }
  }

  /// 只创建应用自己的一级目录，绝不尝试 MKCOL WebDAV 服务路径本身
  /// （例如坚果云 /dav/），从根因上避免对服务根目录误操作导致 403。
  Future<void> _ensureCollection(
      String baseUrl, String username, String password) async {
    final collection = _collectionUri(baseUrl);
    final currentStatus = await _propfindStatus(collection, username, password);
    if (currentStatus == 200 || currentStatus == 207) return;
    if (currentStatus == 401) throw Exception(_authError(currentStatus));
    if (currentStatus == 403) {
      throw Exception(_writeForbiddenError(currentStatus));
    }
    if (currentStatus != 404) {
      throw Exception('WebDAV 连接失败（HTTP $currentStatus）：请检查根地址');
    }

    final parent = _parentUri(collection);
    final parentStatus = await _propfindStatus(parent, username, password);
    if (parentStatus == 401 || parentStatus == 403) {
      throw Exception(_authError(parentStatus));
    }
    if (parentStatus != 200 && parentStatus != 207) {
      throw Exception('WebDAV 根地址不存在（HTTP $parentStatus），请检查服务器地址');
    }

    final createStatus = await _mkcol(collection, username, password);
    if (createStatus == 401) throw Exception(_authError(createStatus));
    if (createStatus == 403) {
      throw Exception(_writeForbiddenError(createStatus));
    }
    final created =
        (createStatus >= 200 && createStatus < 300) || createStatus == 405;
    if (!created) {
      throw Exception('自动创建 $_collectionName 文件夹失败（HTTP $createStatus）：'
          '请确认 WebDAV 账号拥有写入权限');
    }
  }

  Future<int> _propfindStatus(Uri uri, String username, String password) async {
    final client = http.Client();
    try {
      final request = http.Request('PROPFIND', uri);
      request.headers.addAll({
        ..._authHeaders(username, password),
        'Depth': '0',
      });
      final response = await client.send(request);
      await response.stream.drain();
      return response.statusCode;
    } finally {
      client.close();
    }
  }

  Future<int> _mkcol(Uri uri, String username, String password) async {
    final client = http.Client();
    try {
      final request = http.Request('MKCOL', uri);
      request.headers.addAll(_authHeaders(username, password));
      final response = await client.send(request);
      await response.stream.drain();
      return response.statusCode;
    } finally {
      client.close();
    }
  }

  String _authError(int status) =>
      'WebDAV 认证失败（HTTP $status）：请检查用户名与密码，坚果云需使用应用密码';

  String _writeForbiddenError(int status) =>
      'WebDAV 写入被拒（HTTP $status）：应用已尝试自动创建 $_collectionName 文件夹，'
      '请确认当前账号对该根地址具有新建文件夹和上传文件权限';

  String _pushError(int status) {
    switch (status) {
      case 401:
        return _authError(status);
      case 403:
        return _writeForbiddenError(status);
      case 404:
      case 409:
        return 'WebDAV 写入路径不存在（HTTP $status），请检查服务器根地址';
      default:
        return 'WebDAV 推送失败（HTTP $status）';
    }
  }

  Map<String, String> _authHeaders(String username, String password) => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('$username:$password'))}',
      };

  /// 兼容旧配置：若用户已经填写到 /EasyPassword/，直接沿用；否则只在
  /// 所填根地址后追加该目录。统一补尾斜杠，保证各设备派生相同同步密钥。
  Uri _collectionUri(String baseUrl) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      throw Exception('WebDAV 地址格式无效，请填写完整的 http(s) 地址');
    }
    var path = uri.path;
    if (!path.endsWith('/')) path = '$path/';
    final segments = path.split('/').where((part) => part.isNotEmpty).toList();
    if (segments.isEmpty ||
        segments.last.toLowerCase() != _collectionName.toLowerCase()) {
      path = '$path$_collectionName/';
    }
    return uri.replace(path: path);
  }

  Uri _parentUri(Uri collection) {
    final segments =
        collection.pathSegments.where((part) => part.isNotEmpty).toList();
    if (segments.isNotEmpty) segments.removeLast();
    final path = segments.isEmpty ? '/' : '/${segments.join('/')}/';
    return collection.replace(path: path);
  }

  Uri _resolveFileUri(String baseUrl, String fileName) {
    final collection = _collectionUri(baseUrl);
    return collection.replace(path: '${collection.path}$fileName');
  }

  String _syncIdentity(String baseUrl) {
    final uri = _collectionUri(baseUrl);
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          fragment: '',
        )
        .toString();
  }

  String _syncSecret(String username, String password) =>
      '$username\u0000$password';

  // ================= 三种用户同步模式 =================

  /// 本地覆盖远端：明确的强制上传，不拉取也不合并。
  Future<SyncSummary> overwriteRemote(
      String baseUrl, String username, String password) async {
    final highWaterMark = await DatabaseService.getSyncJournalHighWaterMark();
    final snapshot = await buildSnapshot(
      baseUrl: baseUrl,
      username: username,
      password: password,
    );
    await pushSnapshot(baseUrl, username, password, snapshot);
    await DatabaseService.clearSyncJournalThrough(highWaterMark);
    return const SyncSummary(merged: 0, pushed: true);
  }

  /// 远端覆盖本地：明确的强制下载；远端不存在时拒绝清空本地。
  Future<SyncSummary> overwriteLocal(
      String baseUrl, String username, String password) async {
    final remote = await _pullRemote(baseUrl, username, password);
    if (remote.body == null) {
      throw Exception('远端还没有同步快照，不能覆盖本地数据');
    }
    final merged = await replaceLocalSnapshot(
      remote.body!,
      baseUrl: baseUrl,
      username: username,
      password: password,
    );
    final highWaterMark = await DatabaseService.getSyncJournalHighWaterMark();
    await DatabaseService.clearSyncJournalThrough(highWaterMark);
    return SyncSummary(merged: merged, pushed: false);
  }

  /// 自动同步：远端与本地逐行合并后推送。遇到 ETag 冲突最多重试三次，
  /// 覆盖正常网络抖动和多台设备几乎同时同步的场景。
  Future<SyncSummary> syncAll(
      String baseUrl, String username, String password) async {
    var merged = 0;
    for (var attempt = 0; attempt < 3; attempt++) {
      final remote = await _pullRemote(baseUrl, username, password);
      if (remote.body != null) {
        merged += await mergeSnapshot(
          remote.body!,
          baseUrl: baseUrl,
          username: username,
          password: password,
        );
      }
      final highWaterMark = await DatabaseService.getSyncJournalHighWaterMark();
      final snapshot = await buildSnapshot(
        baseUrl: baseUrl,
        username: username,
        password: password,
      );
      try {
        await _putRemote(
          baseUrl,
          username,
          password,
          snapshot,
          expectedEtag: remote.etag,
          onlyIfMissing: remote.body == null,
        );
        await DatabaseService.clearSyncJournalThrough(highWaterMark);
        return SyncSummary(merged: merged, pushed: true);
      } on _RemoteChangedException {
        if (attempt == 2) {
          throw Exception('远端正在被其他设备更新，请稍后重试');
        }
      }
    }
    throw Exception('自动同步未完成，请稍后重试');
  }
}

class SyncSummary {
  final int merged;
  final bool pushed;
  const SyncSummary({required this.merged, required this.pushed});
}

class _RemoteSnapshot {
  final String? body;
  final String? etag;
  const _RemoteSnapshot({required this.body, required this.etag});
}

class _RemoteChangedException implements Exception {
  const _RemoteChangedException();
}
