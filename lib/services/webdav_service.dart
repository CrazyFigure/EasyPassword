/// WebDAV 多端同步服务：跨设备加密快照、删除墓碑与逐行最后修改者胜。
/// 自动同步始终先合并本地与远端，再用条件写入防止并发设备互相覆盖。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../core/app_environment.dart';
import '../core/constants.dart';
import 'crypto_service.dart';
import 'data_service.dart';
import 'database.dart';

/// 用户可选择的三种同步方向。
enum WebDavSyncMode { localToRemote, remoteToLocal, automatic }

class WebDavService {
  final CryptoService crypto;
  final DataService data;

  WebDavService(this.crypto, this.data);

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
    String remotePath = WebDavDefaults.remotePath,
  }) async {
    final payload = jsonEncode(await exportAll());
    if (baseUrl == null) return crypto.encrypt(payload);
    return crypto.encryptForSync(
      payload,
      _syncSecret(username, password),
      _syncIdentity(baseUrl, remotePath),
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
    String remotePath = WebDavDefaults.remotePath,
  }) async {
    final snapshot = await _decodeSnapshot(
      encryptedSnapshot,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remotePath: remotePath,
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
    String remotePath = WebDavDefaults.remotePath,
  }) async {
    final snapshot = await _decodeSnapshot(
      encryptedSnapshot,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remotePath: remotePath,
    );
    return _applySnapshot(snapshot, replaceLocal: true);
  }

  /// 解密并校验快照基本结构，错误凭据和损坏内容都给出可操作提示。
  Future<Map<String, dynamic>> _decodeSnapshot(
    String encryptedSnapshot, {
    String? baseUrl,
    required String username,
    required String password,
    String remotePath = WebDavDefaults.remotePath,
  }) async {
    final jsonText = baseUrl == null
        ? await crypto.decrypt(encryptedSnapshot)
        : await crypto.decryptForSync(
            encryptedSnapshot,
            _syncSecret(username, password),
            _syncIdentity(baseUrl, remotePath),
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

  /// 测试连接同时验证写权限；应用会在 WebDAV 根地址下自动逐级创建用户
  /// 指定的远端路径，不再要求提前进入网页端手工建目录。
  Future<void> testConnection(
    String baseUrl,
    String username,
    String password, {
    String remotePath = WebDavDefaults.remotePath,
  }) async {
    await _ensureCollection(
      baseUrl,
      username,
      password,
      remotePath: remotePath,
    );
  }

  /// 拉取远端快照；文件尚不存在时返回 null。
  Future<String?> pullSnapshot(
    String baseUrl,
    String username,
    String password, {
    String remotePath = WebDavDefaults.remotePath,
  }) async {
    return (await _pullRemote(
      baseUrl,
      username,
      password,
      remotePath: remotePath,
    ))
        .body;
  }

  /// 无条件推送快照，供明确选择“本地覆盖远端”的操作使用。
  Future<void> pushSnapshot(
    String baseUrl,
    String username,
    String password,
    String encrypted, {
    String remotePath = WebDavDefaults.remotePath,
  }) async {
    await _putRemote(
      baseUrl,
      username,
      password,
      encrypted,
      remotePath: remotePath,
    );
  }

  Future<_RemoteSnapshot> _pullRemote(
    String baseUrl,
    String username,
    String password, {
    String remotePath = WebDavDefaults.remotePath,
  }) async {
    await _ensureCollection(
      baseUrl,
      username,
      password,
      remotePath: remotePath,
    );
    final uri = _resolveFileUri(
      baseUrl,
      remotePath,
      AppEnvironment.webDavSnapshotFileName,
    );
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
    String remotePath = WebDavDefaults.remotePath,
    String? expectedEtag,
    bool onlyIfMissing = false,
  }) async {
    await _ensureCollection(
      baseUrl,
      username,
      password,
      remotePath: remotePath,
    );
    final headers = <String, String>{
      ..._authHeaders(username, password),
      'Content-Type': 'application/octet-stream',
      if (expectedEtag != null) 'If-Match': expectedEtag,
      if (onlyIfMissing) 'If-None-Match': '*',
    };
    final response = await http.put(
      _resolveFileUri(
        baseUrl,
        remotePath,
        AppEnvironment.webDavSnapshotFileName,
      ),
      headers: headers,
      body: encrypted,
    );
    if (response.statusCode == 412) throw const _RemoteChangedException();
    if (response.statusCode >= 300) {
      throw Exception(_pushError(response.statusCode, remotePath));
    }
  }

  /// 先验证服务器根地址，再逐级检查/创建配置路径。创建范围严格限制在
  /// 根地址之下，绝不尝试对坚果云 `/dav/` 等服务目录本身执行 MKCOL。
  Future<void> _ensureCollection(
    String baseUrl,
    String username,
    String password, {
    required String remotePath,
  }) async {
    final target = _collectionTarget(baseUrl, remotePath);
    final currentStatus =
        await _propfindStatus(target.collection, username, password);
    if (currentStatus == 200 || currentStatus == 207) return;
    if (currentStatus == 401) throw Exception(_authError(currentStatus));
    if (currentStatus == 403) {
      throw Exception(_writeForbiddenError(currentStatus, target.path));
    }
    if (currentStatus != 404) {
      throw Exception('WebDAV 连接失败（HTTP $currentStatus）：请检查根地址');
    }

    final rootStatus = await _propfindStatus(target.root, username, password);
    if (rootStatus == 401) throw Exception(_authError(rootStatus));
    if (rootStatus == 403) {
      throw Exception(_writeForbiddenError(rootStatus, target.path));
    }
    if (rootStatus != 200 && rootStatus != 207) {
      throw Exception('WebDAV 根地址不存在（HTTP $rootStatus），请检查服务器地址');
    }

    var current = target.root;
    for (final segment in target.segments) {
      current = current.replace(
        pathSegments: [
          ...current.pathSegments.where((part) => part.isNotEmpty),
          segment,
          '',
        ],
      );
      final status = await _propfindStatus(current, username, password);
      if (status == 200 || status == 207) continue;
      if (status == 401) throw Exception(_authError(status));
      if (status == 403) {
        throw Exception(_writeForbiddenError(status, target.path));
      }
      if (status != 404) {
        throw Exception('检查远端路径 ${target.path} 失败（HTTP $status）');
      }

      final createStatus = await _mkcol(current, username, password);
      if (createStatus == 401) throw Exception(_authError(createStatus));
      if (createStatus == 403) {
        throw Exception(_writeForbiddenError(createStatus, target.path));
      }
      final created =
          (createStatus >= 200 && createStatus < 300) || createStatus == 405;
      if (!created) {
        throw Exception('自动创建远端路径 ${target.path} 失败（HTTP $createStatus）：'
            '请确认 WebDAV 账号拥有新建目录权限');
      }
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

  String _writeForbiddenError(int status, String remotePath) =>
      'WebDAV 写入被拒（HTTP $status）：应用已尝试自动创建 $remotePath，'
      '请确认当前账号对该根地址具有新建文件夹和上传文件权限';

  String _pushError(int status, String remotePath) {
    switch (status) {
      case 401:
        return _authError(status);
      case 403:
        return _writeForbiddenError(status, remotePath);
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

  /// 解析服务器根地址与配置路径。若旧配置的服务器地址已经以相同路径结尾，
  /// 会拆回同一个根地址，避免升级后形成 `/EasyPassword/EasyPassword/`。
  _CollectionTarget _collectionTarget(String baseUrl, String remotePath) {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty) {
      throw Exception('WebDAV 地址格式无效，请填写完整的 http(s) 地址');
    }
    if (uri.hasQuery || uri.hasFragment) {
      throw Exception('WebDAV 根地址不能包含查询参数或片段');
    }

    final path = normalizeRemotePath(remotePath);
    final remoteSegments =
        path.split('/').where((part) => part.isNotEmpty).toList();
    final baseSegments =
        uri.pathSegments.where((part) => part.isNotEmpty).toList();
    final includesPath = baseSegments.length >= remoteSegments.length &&
        List.generate(
          remoteSegments.length,
          (index) =>
              baseSegments[baseSegments.length - remoteSegments.length + index]
                  .toLowerCase() ==
              remoteSegments[index].toLowerCase(),
        ).every((matches) => matches);
    final rootSegments = includesPath
        ? baseSegments.sublist(0, baseSegments.length - remoteSegments.length)
        : baseSegments;
    // 旧地址已经包含路径时保留其实际大小写，既兼容区分大小写的服务器，
    // 也确保升级前后使用完全相同的快照加密身份。
    final targetSegments = includesPath
        ? baseSegments.sublist(baseSegments.length - remoteSegments.length)
        : remoteSegments;
    final collectionSegments = [...rootSegments, ...targetSegments];
    return _CollectionTarget(
      root: uri.replace(pathSegments: [...rootSegments, '']),
      collection: uri.replace(pathSegments: [...collectionSegments, '']),
      path: path,
      segments: targetSegments,
    );
  }

  /// 对外暴露统一的路径规范化规则，供设置页在保存成功后回显。
  static String normalizeRemotePath(String remotePath) {
    var value = remotePath.trim().replaceAll('\\', '/');
    if (value.isEmpty) value = WebDavDefaults.remotePath;
    final segments = value.split('/').where((part) => part.isNotEmpty).toList();
    if (segments.isEmpty) {
      throw Exception('WebDAV 远端路径不能为空');
    }
    if (segments.any((part) => part == '.' || part == '..')) {
      throw Exception('WebDAV 远端路径不能包含 . 或 ..');
    }
    return '/${segments.join('/')}';
  }

  Uri _resolveFileUri(String baseUrl, String remotePath, String fileName) {
    final collection = _collectionTarget(baseUrl, remotePath).collection;
    return collection.replace(path: '${collection.path}$fileName');
  }

  String _syncIdentity(String baseUrl, String remotePath) {
    final uri = _collectionTarget(baseUrl, remotePath).collection;
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
  Future<SyncStats> overwriteRemote(
    String baseUrl,
    String username,
    String password, {
    String remotePath = WebDavDefaults.remotePath,
  }) async {
    final localSnapshot = await exportAll();
    final localRows = _extractRows(localSnapshot);
    final activeCount = _countActiveItems(localRows);

    final highWaterMark = await DatabaseService.getSyncJournalHighWaterMark();
    final snapshot = await buildSnapshot(
      baseUrl: baseUrl,
      username: username,
      password: password,
      remotePath: remotePath,
    );
    await pushSnapshot(
      baseUrl,
      username,
      password,
      snapshot,
      remotePath: remotePath,
    );
    await DatabaseService.clearSyncJournalThrough(highWaterMark);
    return SyncStats(
      mode: WebDavSyncMode.localToRemote,
      overwriteCount: activeCount,
    );
  }

  /// 远端覆盖本地：明确的强制下载；远端不存在时拒绝清空本地。
  Future<SyncStats> overwriteLocal(
    String baseUrl,
    String username,
    String password, {
    String remotePath = WebDavDefaults.remotePath,
  }) async {
    final remote = await _pullRemote(
      baseUrl,
      username,
      password,
      remotePath: remotePath,
    );
    if (remote.body == null) {
      throw Exception('远端还没有同步快照，不能覆盖本地数据');
    }
    final remoteSnapshot = await _decodeSnapshot(
      remote.body!,
      baseUrl: baseUrl,
      username: username,
      password: password,
      remotePath: remotePath,
    );
    final remoteRows = _extractRows(remoteSnapshot);
    final activeCount = _countActiveItems(remoteRows);

    await _applySnapshot(remoteSnapshot, replaceLocal: true);
    final highWaterMark = await DatabaseService.getSyncJournalHighWaterMark();
    await DatabaseService.clearSyncJournalThrough(highWaterMark);
    return SyncStats(
      mode: WebDavSyncMode.remoteToLocal,
      overwriteCount: activeCount,
    );
  }

  /// 自动同步：远端与本地逐行合并后推送。遇到 ETag 冲突最多重试三次，
  /// 覆盖正常网络抖动和多台设备几乎同时同步的场景。
  Future<SyncStats> syncAll(
    String baseUrl,
    String username,
    String password, {
    String remotePath = WebDavDefaults.remotePath,
  }) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      // 1. 记录合并前的本地快照数据
      final localSnapshotBefore = await exportAll();
      final localRowsBefore = _extractRows(localSnapshotBefore);

      final remote = await _pullRemote(
        baseUrl,
        username,
        password,
        remotePath: remotePath,
      );

      Map<String, dynamic>? remoteSnapshot;
      Map<String, List<Map<String, dynamic>>>? remoteRowsBefore;

      if (remote.body != null) {
        remoteSnapshot = await _decodeSnapshot(
          remote.body!,
          baseUrl: baseUrl,
          username: username,
          password: password,
          remotePath: remotePath,
        );
        remoteRowsBefore = _extractRows(remoteSnapshot);
        await _applySnapshot(remoteSnapshot, replaceLocal: false);
      }

      final highWaterMark = await DatabaseService.getSyncJournalHighWaterMark();
      final mergedSnapshot = await exportAll();
      final mergedRowsAfter = _extractRows(mergedSnapshot);

      final snapshot = await buildSnapshot(
        baseUrl: baseUrl,
        username: username,
        password: password,
        remotePath: remotePath,
      );
      try {
        await _putRemote(
          baseUrl,
          username,
          password,
          snapshot,
          remotePath: remotePath,
          expectedEtag: remote.etag,
          onlyIfMissing: remote.body == null,
        );
        await DatabaseService.clearSyncJournalThrough(highWaterMark);

        // 2. 计算本地拉取差量（localRowsBefore -> mergedRowsAfter）
        final localDiff = _computeSnapshotDiff(
          localRowsBefore,
          mergedRowsAfter,
        );

        // 3. 计算远端推送差量（remoteRowsBefore -> mergedRowsAfter）
        // 远端首次创建快照时同样按实体逐项统计，避免只统计顶层条目、
        // 漏掉用户、API Key 与设置。
        final remoteDiff = _computeSnapshotDiff(
          remoteRowsBefore ?? const <String, List<Map<String, dynamic>>>{},
          mergedRowsAfter,
        );

        return SyncStats._detailed(
          mode: WebDavSyncMode.automatic,
          localDiff: localDiff,
          remoteDiff: remoteDiff,
        );
      } on _RemoteChangedException {
        if (attempt == 2) {
          throw Exception('远端正在被其他设备更新，请稍后重试');
        }
      }
    }
    throw Exception('自动同步未完成，请稍后重试');
  }

  // ================= 差量对比辅助方法 =================

  /// 计算两个快照版本之间各类同步实体的增删改差量。
  ///
  /// API Key 只保存 account_id，并不直接保存 item_id；旧实现尝试按 item_id
  /// 将它归到网站，导致 API Key 单独增删改时统计为零。这里直接逐表比较，
  /// 同时把账号与设置纳入摘要，确保“确实同步但提示无变更”的情况不再出现。
  static _DiffResult _computeSnapshotDiff(
    Map<String, List<Map<String, dynamic>>> fromRows,
    Map<String, List<Map<String, dynamic>>> toRows,
  ) {
    return _DiffResult(
      folders: _computeTableDiff(fromRows['folders'], toRows['folders'], const [
        'name',
        'type',
        'color',
        'sort_order',
      ]),
      items: _computeTableDiff(
        fromRows['password_items'],
        toRows['password_items'],
        const ['name', 'type', 'url', 'site_note', 'folder_id', 'sort_order'],
      ),
      accounts: _computeTableDiff(
        fromRows['accounts'],
        toRows['accounts'],
        const [
          'item_id',
          'username',
          'password_plain',
          'password_enc',
          'note',
          'sort_order',
        ],
      ),
      apiKeys: _computeTableDiff(
        fromRows['api_keys'],
        toRows['api_keys'],
        const ['account_id', 'key_plain', 'key_enc', 'note', 'sort_order'],
      ),
      settings: _computeTableDiff(
        fromRows['settings'],
        toRows['settings'],
        const ['value'],
        keyColumn: 'key',
        hasDeletedFlag: false,
      ),
    );
  }

  /// 逐行比较单张同步表。软删除恢复按新增计数，墓碑按删除计数；设置表
  /// 没有 deleted 字段，因此通过 [hasDeletedFlag] 关闭墓碑语义。
  static _EntityDiff _computeTableDiff(
    List<Map<String, dynamic>>? fromList,
    List<Map<String, dynamic>>? toList,
    List<String> checkFields, {
    String keyColumn = 'id',
    bool hasDeletedFlag = true,
  }) {
    final fromRows = {
      for (final row in fromList ?? const <Map<String, dynamic>>[])
        if ((row[keyColumn]?.toString() ?? '').isNotEmpty)
          row[keyColumn].toString(): row,
    };
    final toRows = {
      for (final row in toList ?? const <Map<String, dynamic>>[])
        if ((row[keyColumn]?.toString() ?? '').isNotEmpty)
          row[keyColumn].toString(): row,
    };
    var added = 0;
    var updated = 0;
    var deleted = 0;

    for (final entry in toRows.entries) {
      final toRow = entry.value;
      final fromRow = fromRows[entry.key];
      final toDeleted = hasDeletedFlag && toRow['deleted'] == 1;
      if (fromRow == null) {
        if (!toDeleted) added++;
        continue;
      }

      final fromDeleted = hasDeletedFlag && fromRow['deleted'] == 1;
      if (!fromDeleted && toDeleted) {
        deleted++;
      } else if (fromDeleted && !toDeleted) {
        added++;
      } else if (!fromDeleted &&
          !toDeleted &&
          _hasFieldChanges(fromRow, toRow, checkFields)) {
        updated++;
      }
    }

    for (final entry in fromRows.entries) {
      final wasDeleted = hasDeletedFlag && entry.value['deleted'] == 1;
      if (!wasDeleted && !toRows.containsKey(entry.key)) deleted++;
    }
    return _EntityDiff(added: added, updated: updated, deleted: deleted);
  }

  /// 只比较会影响用户可见内容的业务字段，忽略 updated_at、created_at 等
  /// 同步元数据，避免把单纯的时间戳差异误报为内容修改。
  static bool _hasFieldChanges(
    Map<String, dynamic> fromRow,
    Map<String, dynamic> toRow,
    List<String> checkFields,
  ) {
    for (final field in checkFields) {
      if (fromRow.containsKey(field) || toRow.containsKey(field)) {
        if (fromRow[field]?.toString() != toRow[field]?.toString()) return true;
      }
    }
    return false;
  }

  static int _countActiveItems(Map<String, List<Map<String, dynamic>>> rows) {
    final activeFolders =
        (rows['folders'] ?? []).where((f) => f['deleted'] != 1).length;
    final activeItems =
        (rows['password_items'] ?? []).where((i) => i['deleted'] != 1).length;
    return activeFolders + activeItems;
  }
}

/// 单类同步实体的增删改计数。
class _EntityDiff {
  final int added;
  final int updated;
  final int deleted;

  const _EntityDiff({this.added = 0, this.updated = 0, this.deleted = 0});

  bool get hasChanges => added > 0 || updated > 0 || deleted > 0;
}

/// 内部差量计算结果：分别保留每类实体，供同步提示生成准确摘要。
class _DiffResult {
  final _EntityDiff folders;
  final _EntityDiff items;
  final _EntityDiff accounts;
  final _EntityDiff apiKeys;
  final _EntityDiff settings;

  const _DiffResult({
    this.folders = const _EntityDiff(),
    this.items = const _EntityDiff(),
    this.accounts = const _EntityDiff(),
    this.apiKeys = const _EntityDiff(),
    this.settings = const _EntityDiff(),
  });

  int get added =>
      folders.added +
      items.added +
      accounts.added +
      apiKeys.added +
      settings.added;

  int get updated =>
      folders.updated +
      items.updated +
      accounts.updated +
      apiKeys.updated +
      settings.updated;

  int get deleted =>
      folders.deleted +
      items.deleted +
      accounts.deleted +
      apiKeys.deleted +
      settings.deleted;

  bool get hasChanges =>
      folders.hasChanges ||
      items.hasChanges ||
      accounts.hasChanges ||
      apiKeys.hasChanges ||
      settings.hasChanges;

  /// 按操作类型组织文案，避免同一实体的增删改被拆成重复方向描述。
  String toSummaryText() {
    final operations = <String>[];
    for (final operation in const ['新增', '修改', '删除']) {
      final entities = <String>[];
      _addEntityText(entities, operation, folders, '个文件夹');
      _addEntityText(entities, operation, items, '个条目');
      _addEntityText(entities, operation, accounts, '个用户');
      _addEntityText(entities, operation, apiKeys, '个 API Key');
      _addEntityText(entities, operation, settings, '项设置');
      if (entities.isNotEmpty) {
        operations.add('$operation ${entities.join('、')}');
      }
    }
    return operations.join('，');
  }

  static void _addEntityText(
    List<String> parts,
    String operation,
    _EntityDiff diff,
    String unit,
  ) {
    final count = switch (operation) {
      '新增' => diff.added,
      '修改' => diff.updated,
      '删除' => diff.deleted,
      _ => 0,
    };
    if (count > 0) parts.add('$count $unit');
  }
}

/// WebDAV 同步结果统计模型：记录双向增删改明细与全量覆盖条目数
class SyncStats {
  /// 本地拉取变更统计
  final int localAdded;
  final int localUpdated;
  final int localDeleted;

  /// 远端推送变更统计
  final int remoteAdded;
  final int remoteUpdated;
  final int remoteDeleted;

  /// 全量覆盖条目总数（覆盖本地时为拉取数，覆盖远端时为推送数）
  final int? overwriteCount;
  final WebDavSyncMode mode;

  /// 自动同步的分类明细。旧调用方仍可只传汇总计数，保持兼容。
  final _DiffResult? _localDiff;
  final _DiffResult? _remoteDiff;

  const SyncStats({
    this.localAdded = 0,
    this.localUpdated = 0,
    this.localDeleted = 0,
    this.remoteAdded = 0,
    this.remoteUpdated = 0,
    this.remoteDeleted = 0,
    this.overwriteCount,
    required this.mode,
  }) : _localDiff = null,
       _remoteDiff = null;

  /// 自动同步内部使用的明细构造器，汇总字段继续保留，避免破坏既有调用。
  SyncStats._detailed({
    required this.mode,
    required _DiffResult localDiff,
    required _DiffResult remoteDiff,
  }) : localAdded = localDiff.added,
       localUpdated = localDiff.updated,
       localDeleted = localDiff.deleted,
       remoteAdded = remoteDiff.added,
       remoteUpdated = remoteDiff.updated,
       remoteDeleted = remoteDiff.deleted,
       overwriteCount = null,
       _localDiff = localDiff,
       _remoteDiff = remoteDiff;

  /// 是否产生了增量数据变更
  bool get hasChanges =>
      localAdded > 0 ||
      localUpdated > 0 ||
      localDeleted > 0 ||
      remoteAdded > 0 ||
      remoteUpdated > 0 ||
      remoteDeleted > 0;

  /// 生成易读的同步结果摘要文案
  String toSummaryMessage() {
    switch (mode) {
      case WebDavSyncMode.localToRemote:
        final count = overwriteCount ?? 0;
        return '全量覆盖远端完成：已推送全部 $count 个条目';
      case WebDavSyncMode.remoteToLocal:
        final count = overwriteCount ?? 0;
        return '全量覆盖本地完成：已覆盖 $count 个条目';
      case WebDavSyncMode.automatic:
        if (!hasChanges) {
          return '同步完成：无数据变更';
        }
        final parts = <String>[];
        if (_localDiff != null || _remoteDiff != null) {
          if (_localDiff?.hasChanges ?? false) {
            parts.add('本地拉取${_localDiff!.toSummaryText()}');
          }
          if (_remoteDiff?.hasChanges ?? false) {
            parts.add('远端推送${_remoteDiff!.toSummaryText()}');
          }
          return '同步完成：${parts.join('；')}';
        }

        // 兼容外部按旧汇总字段构造 SyncStats 的场景。
        final localParts = <String>[];
        if (localAdded > 0) localParts.add('新增 $localAdded 条');
        if (localUpdated > 0) localParts.add('修改 $localUpdated 条');
        if (localDeleted > 0) localParts.add('删除 $localDeleted 条');
        if (localParts.isNotEmpty) {
          parts.add('本地拉取${localParts.join('、')}');
        }

        final remoteParts = <String>[];
        if (remoteAdded > 0) remoteParts.add('新增 $remoteAdded 条');
        if (remoteUpdated > 0) remoteParts.add('修改 $remoteUpdated 条');
        if (remoteDeleted > 0) remoteParts.add('删除 $remoteDeleted 条');
        if (remoteParts.isNotEmpty) {
          parts.add('远端推送${remoteParts.join('、')}');
        }

        return '同步完成：${parts.join('；')}';
    }
  }
}

/// 保持对旧代码命名的兼容别名
typedef SyncSummary = SyncStats;

class _RemoteSnapshot {
  final String? body;
  final String? etag;
  const _RemoteSnapshot({required this.body, required this.etag});
}

/// 规范化后的根地址与目标目录。保存逐级目录片段可确保 MKCOL 只发生在
/// 用户填写的服务器根地址之下。
class _CollectionTarget {
  final Uri root;
  final Uri collection;
  final String path;
  final List<String> segments;

  const _CollectionTarget({
    required this.root,
    required this.collection,
    required this.path,
    required this.segments,
  });
}

class _RemoteChangedException implements Exception {
  const _RemoteChangedException();
}
