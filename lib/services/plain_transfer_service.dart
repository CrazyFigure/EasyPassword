/// 明文导出与导入服务：把密码 / API Key 以可读 JSON 备份到本地文件，
/// 或从外部文件恢复。与 WebDAV 快照的关键差异是这里**完全不加密**，
/// 因此文件本身即等同于密码原文，界面必须给出明确风险提示。
///
/// 与多端同步的配合是本服务的设计重点：
/// 1. 导入写库统一使用「导入时刻」作为 updated_at。WebDAV 逐行按
///    updated_at 最后修改者胜（见 WebDavService._remoteWins），只有让导入
///    结果比远端现存行更新，同步才会把导入内容推送给其他设备。
/// 2. 覆盖导入不物理删除多余数据，而是写 deleted = 1 的墓碑。物理删除
///    会让远端旧行在下一轮合并中被当作「本地没有的新数据」重新插入，
///    也就是数据复活；墓碑才能把删除意图正确传播到其他端。
/// 3. 所有写入都经业务表触发器进入 sync_journal，断网时也会保留待推送标记。
///
/// 明文文件只承载密码与 API Key 业务数据，不含应用锁、WebDAV 凭据等设置：
/// 那些字段一旦被外部文件覆盖，可能直接让设备失去解锁或同步能力。
library;

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../core/name_sort.dart';
import 'crypto_service.dart';
import 'data_service.dart';
import 'database.dart';

/// 导入模式。
/// - [merge]：增量导入，只新增与更新，保留本地已有的其他数据；
/// - [replace]：覆盖导入，文件内容成为唯一事实，多余本地数据写入删除墓碑。
enum PlainImportMode { merge, replace }

/// 导入结果统计，用于界面回报实际生效的条数。
class PlainImportResult {
  final int addedItems;
  final int updatedItems;
  final int removedItems;
  final int accounts;
  final int apiKeys;

  const PlainImportResult({
    this.addedItems = 0,
    this.updatedItems = 0,
    this.removedItems = 0,
    this.accounts = 0,
    this.apiKeys = 0,
  });

  /// 界面用的一句话摘要
  String get summary {
    final parts = <String>[
      '新增 $addedItems 项',
      '更新 $updatedItems 项',
      if (removedItems > 0) '删除 $removedItems 项',
      '共 $accounts 个账号',
      if (apiKeys > 0) '$apiKeys 个 API Key',
    ];
    return parts.join('，');
  }
}

/// 导入文件格式非法时抛出，界面直接展示 [message]。
class PlainImportException implements Exception {
  final String message;
  const PlainImportException(this.message);

  @override
  String toString() => message;
}

class PlainTransferService {
  final CryptoService crypto;
  final DataService data;

  PlainTransferService(this.crypto, this.data);

  /// 明文备份格式版本。导入向下兼容，仅在结构调整时递增。
  static const int formatVersion = 1;
  static const String formatTag = 'EasyPassword-plain';

  /// 导出文件的建议文件名前缀
  static const String fileNamePrefix = 'EasyPassword-明文备份';

  /// 约定的本地导出文件名。
  /// 导出会覆盖已有同名文件；导入可指定此路径直接读取，无需文件选择器。
  static const String defaultFileName = 'easypassword-plain-backup.json';

  // ================= 导出 =================

  /// 导出全部未删除数据为可读 JSON 文本。
  ///
  /// 采用嵌套结构（条目 → 账号 → API Key）而不是数据库的扁平四表，
  /// 用户可以直接看懂并手工编辑；文件夹只导出名称，导入端按名称重新
  /// 建立，避免跨设备 id 不一致导致的归属错乱。
  Future<String> exportPlainText() async {
    final db = await DatabaseService.db;
    final folderRows = await db.query(
      'folders',
      where: 'deleted = 0',
      orderBy: 'sort_order ASC',
    );
    // folderId -> 文件夹名，供条目导出时写成可读名称
    final folderNames = {
      for (final row in folderRows)
        row['id'] as String: (row['name'] as String?) ?? '',
    };

    final exportedItems = <Map<String, dynamic>>[];
    for (final type in const [ItemType.password, ItemType.apikey]) {
      final itemRows = await db.query(
        'password_items',
        where: 'type = ? AND deleted = 0',
        whereArgs: [type],
        orderBy: 'sort_order ASC',
      );
      for (final itemRow in itemRows) {
        exportedItems.add(await _exportItem(db, itemRow, folderNames));
      }
    }

    return const JsonEncoder.withIndent('  ').convert({
      'format': formatTag,
      'version': formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'warning': '本文件为明文备份，包含全部密码与 API Key 原文，请妥善保管并在使用后及时删除。',
      // 文件夹独立成节：空文件夹与自定义颜色都要能无损往返，否则「导出后
      // 立刻覆盖导入」会把空文件夹当作多余数据删掉，并把颜色重置为默认。
      'folders': [
        for (final row in folderRows)
          {
            'type': row['type'],
            'name': (row['name'] as String?) ?? '',
            'color': row['color'],
          },
      ],
      'items': exportedItems,
    });
  }

  /// 导出单个条目及其下属账号与 API Key（加密字段解密为明文）
  Future<Map<String, dynamic>> _exportItem(
    DatabaseExecutor db,
    Map<String, dynamic> itemRow,
    Map<String, String> folderNames,
  ) async {
    final accounts = <Map<String, dynamic>>[];
    final accountRows = await db.query(
      'accounts',
      where: 'item_id = ? AND deleted = 0',
      whereArgs: [itemRow['id']],
      orderBy: 'sort_order ASC',
    );
    for (final accountRow in accountRows) {
      final keys = <Map<String, dynamic>>[];
      final keyRows = await db.query(
        'api_keys',
        where: 'account_id = ? AND deleted = 0',
        whereArgs: [accountRow['id']],
        orderBy: 'sort_order ASC',
      );
      for (final keyRow in keyRows) {
        keys.add({
          'key': await crypto.decrypt((keyRow['key_enc'] as String?) ?? ''),
          'note': (keyRow['note'] as String?) ?? '',
        });
      }
      accounts.add({
        'username': (accountRow['username'] as String?) ?? '',
        'password':
            await crypto.decrypt((accountRow['password_enc'] as String?) ?? ''),
        'note': (accountRow['note'] as String?) ?? '',
        // 密码分区条目此处恒为空数组，保持两个分区结构一致便于手工编辑
        'api_keys': keys,
      });
    }

    final folderId = itemRow['folder_id'] as String?;
    return {
      'type': itemRow['type'],
      'name': (itemRow['name'] as String?) ?? '',
      'url': (itemRow['url'] as String?) ?? '',
      'note': (itemRow['site_note'] as String?) ?? '',
      'folder': folderId == null ? '' : (folderNames[folderId] ?? ''),
      'accounts': accounts,
    };
  }

  // ================= 导入 =================

  /// 导入明文备份。[mode] 决定本地多余数据是保留还是写入删除墓碑。
  ///
  /// 解析失败会在写库之前抛出 [PlainImportException]，不会产生半套数据；
  /// 写库整体在一个事务内完成，中途异常自动回滚。
  Future<PlainImportResult> importPlainText(
    String text, {
    required PlainImportMode mode,
  }) async {
    final snapshot = _decode(text);
    final parsedItems = _parse(snapshot);
    final db = await DatabaseService.db;
    // 全部行共用同一个导入时刻：同步比较的是毫秒时间戳，统一取值才能
    // 保证同一次导入的所有改动在其他设备上被整体接受。
    final now = DateTime.now().millisecondsSinceEpoch;

    var added = 0;
    var updated = 0;
    var removed = 0;
    var accountCount = 0;
    var keyCount = 0;

    await db.transaction((txn) async {
      final folders = await _loadFolders(txn);
      final items = await _loadItems(txn, folders.idToName);
      // 覆盖模式据此判断哪些本地行在文件中没有对应项
      final matchedItemIds = <String>{};
      final matchedFolderIds = <String>{};
      // 同一层级新增行的递增序号，保证导入结果保持文件中的顺序
      final nextOrder = <String, int>{};
      // 本次实际写入过条目的层级，收尾时只重排这些，不动用户没碰的部分。
      // 元素形如 (type, folderId)；folderId 为 null 表示根层级。
      final touchedScopes = <(String, String?)>{};

      // 先导入文件夹清单（v1 格式的旧文件无此节，兼容跳过）
      for (final rawFolder in _mapRows(snapshot['folders'])) {
        final type = _string(rawFolder['type']);
        final name = _string(rawFolder['name']).trim();
        if (type.isEmpty || name.isEmpty) continue;
        if (type != ItemType.password && type != ItemType.apikey) continue;
        final colorValue = rawFolder['color'];
        final color = (colorValue is int) ? colorValue : null;

        final folderId = await _ensureFolder(
          txn,
          folders,
          type,
          name,
          now,
          nextOrder,
          touchedScopes,
          color: color,
        );
        matchedFolderIds.add(folderId);
      }

      for (final parsed in parsedItems) {
        String? folderId;
        if (parsed.folder.isNotEmpty) {
          folderId = await _ensureFolder(
            txn,
            folders,
            parsed.type,
            parsed.folder,
            now,
            nextOrder,
            touchedScopes,
          );
          matchedFolderIds.add(folderId);
        }

        final localItem = items.take(parsed.type, parsed.folder, parsed.name);
        final String itemId;
        if (localItem == null) {
          itemId = DataService.genId();
          await txn.insert('password_items', {
            'id': itemId,
            'type': parsed.type,
            'name': parsed.name,
            'url': parsed.url,
            'site_note': parsed.note,
            'folder_id': folderId,
            'sort_order':
                await _takeOrder(txn, nextOrder, parsed.type, folderId),
            'created_at': now,
            'updated_at': now,
            'deleted': 0,
          });
          added++;
          // 新行插在末尾，这个层级需要重排
          touchedScopes.add((parsed.type, folderId));
        } else {
          itemId = localItem['id'] as String;
          matchedItemIds.add(itemId);
          // 比较全部可变字段，任一改动时才更新
          final urlChanged = (localItem['url'] as String?) != parsed.url;
          final noteChanged = (localItem['site_note'] as String?) != parsed.note;
          final folderChanged = (localItem['folder_id'] as String?) != folderId;
          if (folderChanged) {
            // 换了文件夹：来源与目标两个层级的序号都不再连续
            touchedScopes.add((parsed.type, localItem['folder_id'] as String?));
            touchedScopes.add((parsed.type, folderId));
          }
          if (urlChanged || noteChanged || folderChanged) {
            await txn.update(
              'password_items',
              {
                'url': parsed.url,
                'site_note': parsed.note,
                'folder_id': folderId,
                'updated_at': now,
              },
              where: 'id = ?',
              whereArgs: [itemId],
            );
            updated++;
          }
        }

        final childChanged = await _applyAccounts(
          txn,
          itemId: itemId,
          parsedAccounts: parsed.accounts,
          isNewItem: localItem == null,
          replace: mode == PlainImportMode.replace,
          now: now,
        );
        // 条目本身未变但账号有增改时，同样计入「更新」，让统计与用户感知一致
        if (childChanged && localItem != null) {
          final alreadyCounted = (localItem['url'] as String?) != parsed.url ||
              (localItem['site_note'] as String?) != parsed.note;
          if (!alreadyCounted) updated++;
        }

        accountCount += parsed.accounts.length;
        for (final account in parsed.accounts) {
          keyCount += account.apiKeys.length;
        }
      }

      if (mode == PlainImportMode.replace) {
        removed = await _tombstoneMissing(
          txn,
          items: items,
          folders: folders,
          matchedItemIds: matchedItemIds,
          matchedFolderIds: matchedFolderIds,
          now: now,
        );
      }

      // 导入的行按文件顺序拿到递增序号，那个顺序对用户没有意义（AI 识别的
      // 输出顺序尤其随机）。这里按名称规则重排受影响层级的 sort_order，
      // 自定义排序模式下打开列表就已经是整齐的，不必手工拖动。
      await _resortAffectedScopes(txn, touchedScopes, now);
    });

    // 走与普通编辑相同的防抖通道，导入结果会随下一轮自动同步推送到其他设备
    data.notifyChanged();

    return PlainImportResult(
      addedItems: added,
      updatedItems: updated,
      removedItems: removed,
      accounts: accountCount,
      apiKeys: keyCount,
    );
  }

  /// 写入一个条目下的全部账号与 API Key，返回是否发生实际改动。
  ///
  /// 覆盖模式下该条目内本地多余的账号 / Key 一并写入墓碑；增量模式保留。
  Future<bool> _applyAccounts(
    DatabaseExecutor txn, {
    required String itemId,
    required List<_ParsedAccount> parsedAccounts,
    required bool isNewItem,
    required bool replace,
    required int now,
  }) async {
    var changed = false;
    final localAccounts = isNewItem
        ? <Map<String, dynamic>>[]
        : await txn.query(
            'accounts',
            where: 'item_id = ? AND deleted = 0',
            whereArgs: [itemId],
            orderBy: 'sort_order ASC',
          );
    // 同一条目内允许同名账号，按出现顺序逐个消费匹配，避免全部落到第一条。
    // 匹配命中的行会移出 pending，循环结束后剩下的就是文件中不存在的账号。
    final pending = List<Map<String, dynamic>>.from(localAccounts);
    var nextOrder = pending.fold<int>(
          -1,
          (max, row) {
            final order = (row['sort_order'] as int?) ?? 0;
            return order > max ? order : max;
          },
        ) +
        1;

    for (final parsed in parsedAccounts) {
      final index = pending
          .indexWhere((row) => (row['username'] as String?) == parsed.username);
      final local = index < 0 ? null : pending.removeAt(index);
      final String accountId;
      if (local == null) {
        accountId = DataService.genId();
        await txn.insert('accounts', {
          'id': accountId,
          'item_id': itemId,
          'username': parsed.username,
          'password_enc': await crypto.encrypt(parsed.password),
          'note': parsed.note,
          'sort_order': nextOrder++,
          'created_at': now,
          'updated_at': now,
          'deleted': 0,
        });
        changed = true;
      } else {
        accountId = local['id'] as String;
        final localPassword =
            await crypto.decrypt((local['password_enc'] as String?) ?? '');
        final noteChanged = (local['note'] as String?) != parsed.note;
        if (localPassword != parsed.password || noteChanged) {
          await txn.update(
            'accounts',
            {
              // 密码逐条重新加密，导入后的密文与本机其他数据使用同一把密钥
              'password_enc': await crypto.encrypt(parsed.password),
              'note': parsed.note,
              'updated_at': now,
            },
            where: 'id = ?',
            whereArgs: [accountId],
          );
          changed = true;
        }
      }

      if (await _applyApiKeys(
        txn,
        accountId: accountId,
        parsedKeys: parsed.apiKeys,
        isNewAccount: local == null,
        replace: replace,
        now: now,
      )) {
        changed = true;
      }
    }

    if (replace) {
      // 文件中不存在的账号写墓碑；其下 API Key 一并软删，语义与 deleteAccount 一致
      for (final leftover in pending) {
        final id = leftover['id'] as String;
        await txn.rawUpdate(
          'UPDATE accounts SET deleted = 1, updated_at = ? WHERE id = ?',
          [now, id],
        );
        await txn.rawUpdate(
          'UPDATE api_keys SET deleted = 1, updated_at = ? '
          'WHERE account_id = ? AND deleted = 0',
          [now, id],
        );
        changed = true;
      }
    }
    return changed;
  }

  /// 写入一个账号下的全部 API Key，返回是否发生实际改动。
  Future<bool> _applyApiKeys(
    DatabaseExecutor txn, {
    required String accountId,
    required List<_ParsedApiKey> parsedKeys,
    required bool isNewAccount,
    required bool replace,
    required int now,
  }) async {
    var changed = false;
    final localKeys = isNewAccount
        ? <Map<String, dynamic>>[]
        : await txn.query(
            'api_keys',
            where: 'account_id = ? AND deleted = 0',
            whereArgs: [accountId],
            orderBy: 'sort_order ASC',
          );
    // 预解密一次，后续匹配与比较都复用，避免同一行反复走 AES
    final pending = <({Map<String, dynamic> row, String key})>[];
    for (final row in localKeys) {
      pending.add((
        row: row,
        key: await crypto.decrypt((row['key_enc'] as String?) ?? ''),
      ));
    }
    var nextOrder = pending.fold<int>(
          -1,
          (max, entry) {
            final order = (entry.row['sort_order'] as int?) ?? 0;
            return order > max ? order : max;
          },
        ) +
        1;

    for (final parsed in parsedKeys) {
      // API Key 没有天然主键，按「备注与 Key 都相同 → 备注相同 → Key 相同」
      // 三级降级匹配：用户改了其中一个字段时仍能命中原行而不是新建一条。
      var index = pending.indexWhere(
        (entry) =>
            (entry.row['note'] as String?) == parsed.note &&
            entry.key == parsed.key,
      );
      if (index < 0 && parsed.note.isNotEmpty) {
        index = pending
            .indexWhere((entry) => (entry.row['note'] as String?) == parsed.note);
      }
      if (index < 0) {
        index = pending.indexWhere((entry) => entry.key == parsed.key);
      }
      final local = index < 0 ? null : pending.removeAt(index);

      if (local == null) {
        await txn.insert('api_keys', {
          'id': DataService.genId(),
          'account_id': accountId,
          'key_enc': await crypto.encrypt(parsed.key),
          'note': parsed.note,
          'sort_order': nextOrder++,
          'created_at': now,
          'updated_at': now,
          'deleted': 0,
        });
        changed = true;
      } else if (local.key != parsed.key ||
          (local.row['note'] as String?) != parsed.note) {
        await txn.update(
          'api_keys',
          {
            'key_enc': await crypto.encrypt(parsed.key),
            'note': parsed.note,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [local.row['id']],
        );
        changed = true;
      }
    }

    if (replace) {
      for (final leftover in pending) {
        await txn.rawUpdate(
          'UPDATE api_keys SET deleted = 1, updated_at = ? WHERE id = ?',
          [now, leftover.row['id']],
        );
        changed = true;
      }
    }
    return changed;
  }

  /// 按名称规则重排受影响层级的 sort_order，让导入结果立即是有序的。
  ///
  /// 根层级的文件夹与条目共用一套序号（见 DataService._nextRootOrder），
  /// 因此两张表要放在一起排：文件夹整体在前，各组内部按 [compareNames]。
  /// 这与「按名称排序」模式下 AppState.rootEntries 的展示顺序一致，用户切到
  /// 自定义排序时看到的就是同一个顺序，不会突然跳成导入时的随机次序。
  ///
  /// 只有序号真正变化的行才写库：无谓的 updated_at 变动会让同步把整批行
  /// 重新推送一遍，也可能盖掉其他设备上更有意义的修改。
  Future<void> _resortAffectedScopes(
    DatabaseExecutor txn,
    Set<(String, String?)> scopes,
    int now,
  ) async {
    for (final (type, folderId) in scopes) {
      // ('folders'|'password_items', id, 当前序号, 参与比较的名称)
      final rows = <(String, String, int, String)>[];

      if (folderId == null) {
        for (final row in await txn.query(
          'folders',
          columns: ['id', 'name', 'sort_order'],
          where: 'type = ? AND deleted = 0',
          whereArgs: [type],
        )) {
          rows.add((
            'folders',
            row['id'] as String,
            (row['sort_order'] as int?) ?? 0,
            (row['name'] as String?) ?? '',
          ));
        }
      }

      final itemRows = folderId == null
          ? await txn.query(
              'password_items',
              columns: ['id', 'name', 'sort_order'],
              where: 'type = ? AND deleted = 0 AND folder_id IS NULL',
              whereArgs: [type],
            )
          : await txn.query(
              'password_items',
              columns: ['id', 'name', 'sort_order'],
              where: 'type = ? AND deleted = 0 AND folder_id = ?',
              whereArgs: [type, folderId],
            );
      final itemStart = rows.length;
      for (final row in itemRows) {
        rows.add((
          'password_items',
          row['id'] as String,
          (row['sort_order'] as int?) ?? 0,
          (row['name'] as String?) ?? '',
        ));
      }

      // 文件夹段与条目段各自排序，再顺序拼接，保证文件夹恒在前
      final folderPart = rows.sublist(0, itemStart)
        ..sort((a, b) => compareNames(a.$4, b.$4));
      final itemPart = rows.sublist(itemStart)
        ..sort((a, b) => compareNames(a.$4, b.$4));
      final ordered = [...folderPart, ...itemPart];

      for (var i = 0; i < ordered.length; i++) {
        final (table, id, currentOrder, _) = ordered[i];
        if (currentOrder == i) continue;
        await txn.rawUpdate(
          'UPDATE $table SET sort_order = ?, updated_at = ? WHERE id = ?',
          [i, now, id],
        );
      }
    }
  }

  /// 覆盖模式收尾：为文件中不存在的本地条目与文件夹写入删除墓碑。
  /// 返回被删除的顶层条目数。
  Future<int> _tombstoneMissing(
    DatabaseExecutor txn, {
    required _ItemIndex items,
    required _FolderIndex folders,
    required Set<String> matchedItemIds,
    required Set<String> matchedFolderIds,
    required int now,
  }) async {
    var removed = 0;
    for (final row in items.all) {
      final id = row['id'] as String;
      if (matchedItemIds.contains(id)) continue;
      await txn.rawUpdate(
        'UPDATE password_items SET deleted = 1, updated_at = ? WHERE id = ?',
        [now, id],
      );
      // 级联软删账号与 API Key，与 DataService.deleteItem 保持一致
      final accounts = await txn.query(
        'accounts',
        columns: ['id'],
        where: 'item_id = ? AND deleted = 0',
        whereArgs: [id],
      );
      for (final account in accounts) {
        await txn.rawUpdate(
          'UPDATE accounts SET deleted = 1, updated_at = ? WHERE id = ?',
          [now, account['id']],
        );
        await txn.rawUpdate(
          'UPDATE api_keys SET deleted = 1, updated_at = ? '
          'WHERE account_id = ? AND deleted = 0',
          [now, account['id']],
        );
      }
      removed++;
    }
    for (final row in folders.all) {
      final id = row['id'] as String;
      if (matchedFolderIds.contains(id)) continue;
      await txn.rawUpdate(
        'UPDATE folders SET deleted = 1, updated_at = ? WHERE id = ?',
        [now, id],
      );
    }
    return removed;
  }

  /// 按 (type, name) 找到或新建文件夹，返回文件夹 id。
  /// [color] 仅在新建时写入；已存在的文件夹保留本机颜色，避免导入反复改色。
  /// 新建文件夹会占用根层级序号，因此把根层级登记进 [touchedScopes] 等待重排。
  Future<String> _ensureFolder(
    DatabaseExecutor txn,
    _FolderIndex folders,
    String type,
    String name,
    int now,
    Map<String, int> nextOrder,
    Set<(String, String?)> touchedScopes, {
    int? color,
  }) async {
    final existing = folders.find(type, name);
    if (existing != null) return existing;
    touchedScopes.add((type, null));
    final id = DataService.genId();
    await txn.insert('folders', {
      'id': id,
      'type': type,
      'name': name,
      'color': color,
      // 文件夹与根目录条目共用一套序号（见 DataService._nextRootOrder）
      'sort_order': await _takeOrder(txn, nextOrder, type, null),
      'created_at': now,
      'updated_at': now,
      'deleted': 0,
    });
    folders.register(id, type, name);
    return id;
  }

  /// 取同一层级的下一个排序号：首次访问时读库取当前最大值，之后本地自增。
  Future<int> _takeOrder(
    DatabaseExecutor txn,
    Map<String, int> cache,
    String type,
    String? folderId,
  ) async {
    final cacheKey = '$type|${folderId ?? ''}';
    final cached = cache[cacheKey];
    if (cached != null) {
      cache[cacheKey] = cached + 1;
      return cached;
    }
    int maxOf(List<Map<String, dynamic>> rows) =>
        (rows.first['m'] as int?) ?? -1;
    final int current;
    if (folderId == null) {
      final itemRows = await txn.rawQuery(
        'SELECT MAX(sort_order) AS m FROM password_items '
        'WHERE type = ? AND deleted = 0 AND folder_id IS NULL',
        [type],
      );
      final folderRows = await txn.rawQuery(
        'SELECT MAX(sort_order) AS m FROM folders WHERE type = ? AND deleted = 0',
        [type],
      );
      final maxItem = maxOf(itemRows);
      final maxFolder = maxOf(folderRows);
      current = (maxItem > maxFolder ? maxItem : maxFolder) + 1;
    } else {
      final rows = await txn.rawQuery(
        'SELECT MAX(sort_order) AS m FROM password_items '
        'WHERE type = ? AND deleted = 0 AND folder_id = ?',
        [type, folderId],
      );
      current = maxOf(rows) + 1;
    }
    cache[cacheKey] = current + 1;
    return current;
  }

  Future<_FolderIndex> _loadFolders(DatabaseExecutor txn) async {
    final rows = await txn.query('folders', where: 'deleted = 0');
    return _FolderIndex(rows);
  }

  Future<_ItemIndex> _loadItems(
      DatabaseExecutor txn, Map<String, String> folderNames) async {
    final rows = await txn.query('password_items', where: 'deleted = 0');
    return _ItemIndex(rows, folderNames);
  }

  // ================= 解析与校验 =================

  /// 解码并基本校验快照，返回完整的顶层 map
  Map<String, dynamic> _decode(String text) {
    if (text.trim().isEmpty) {
      throw const PlainImportException('文件内容为空');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw const PlainImportException('不是有效的 JSON 文件，请确认内容未被截断或修改');
    }
    if (decoded is! Map) {
      throw const PlainImportException('文件结构不正确，顶层应为 JSON 对象');
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// 解析明文 JSON 的 items 节。任何结构问题都在写库之前抛出，并指明出错的位置。
  List<_ParsedItem> _parse(Map<String, dynamic> snapshot) {
    final rawItems = snapshot['items'];
    if (rawItems is! List) {
      throw const PlainImportException('文件缺少 items 列表');
    }

    final parsed = <_ParsedItem>[];
    for (var i = 0; i < rawItems.length; i++) {
      final raw = rawItems[i];
      // 出错位置用「第 N 项」而非数组下标，便于用户在编辑器里定位
      final position = '第 ${i + 1} 项';
      if (raw is! Map) {
        throw PlainImportException('$position 不是有效的条目对象');
      }
      final name = _string(raw['name']).trim();
      if (name.isEmpty) {
        throw PlainImportException('$position 缺少名称');
      }
      final type = _string(raw['type']).trim();
      if (type != ItemType.password && type != ItemType.apikey) {
        throw PlainImportException(
            '$position（$name）的 type 必须是 password 或 apikey');
      }
      final rawAccounts = raw['accounts'];
      if (rawAccounts != null && rawAccounts is! List) {
        throw PlainImportException('$position（$name）的 accounts 必须是列表');
      }

      final accounts = <_ParsedAccount>[];
      for (final rawAccount in (rawAccounts as List?) ?? const []) {
        if (rawAccount is! Map) {
          throw PlainImportException('$position（$name）内含无效的账号对象');
        }
        final rawKeys = rawAccount['api_keys'];
        if (rawKeys != null && rawKeys is! List) {
          throw PlainImportException('$position（$name）的 api_keys 必须是列表');
        }
        final keys = <_ParsedApiKey>[];
        for (final rawKey in (rawKeys as List?) ?? const []) {
          // 允许直接写字符串，手工编辑时可以省掉备注字段
          if (rawKey is String) {
            keys.add(_ParsedApiKey(key: rawKey, note: ''));
          } else if (rawKey is Map) {
            keys.add(_ParsedApiKey(
              key: _string(rawKey['key']),
              note: _string(rawKey['note']),
            ));
          } else {
            throw PlainImportException('$position（$name）内含无效的 API Key');
          }
        }
        accounts.add(_ParsedAccount(
          username: _string(rawAccount['username']),
          password: _string(rawAccount['password']),
          note: _string(rawAccount['note']),
          apiKeys: keys,
        ));
      }

      parsed.add(_ParsedItem(
        type: type,
        name: name,
        url: _string(raw['url']).trim(),
        note: _string(raw['note']),
        folder: _string(raw['folder']).trim(),
        accounts: accounts,
      ));
    }
    return parsed;
  }

  /// 数值、布尔等非字符串值一律转成文本，容忍手工编辑时省略引号
  String _string(Object? value) => value == null ? '' : value.toString();

  List<Map<String, dynamic>> _mapRows(Object? value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return [
      for (final row in value)
        if (row is Map) Map<String, dynamic>.from(row),
    ];
  }
}

/// 解析后的条目（尚未写库）
class _ParsedItem {
  final String type;
  final String name;
  final String url;
  final String note;
  final String folder;
  final List<_ParsedAccount> accounts;

  const _ParsedItem({
    required this.type,
    required this.name,
    required this.url,
    required this.note,
    required this.folder,
    required this.accounts,
  });
}

class _ParsedAccount {
  final String username;
  final String password;
  final String note;
  final List<_ParsedApiKey> apiKeys;

  const _ParsedAccount({
    required this.username,
    required this.password,
    required this.note,
    required this.apiKeys,
  });
}

class _ParsedApiKey {
  final String key;
  final String note;

  const _ParsedApiKey({required this.key, required this.note});
}

/// 本地文件夹索引：按 (type, name) 查找，支持导入过程中登记新建项
class _FolderIndex {
  final List<Map<String, dynamic>> all;
  final Map<String, String> _byKey = {};
  final Map<String, String> idToName = {};

  _FolderIndex(this.all) {
    for (final row in all) {
      final id = row['id'] as String;
      final name = (row['name'] as String?) ?? '';
      idToName[id] = name;
      // 同名文件夹保留先出现的一个，导入统一归入它，不再产生重复目录
      _byKey.putIfAbsent('${row['type']}|$name', () => id);
    }
  }

  String? find(String type, String name) => _byKey['$type|$name'];

  void register(String id, String type, String name) {
    idToName[id] = name;
    _byKey.putIfAbsent('$type|$name', () => id);
  }
}

/// 本地条目索引：按 (type, 文件夹名, 条目名) 查找。
/// 明文文件不含 id，只能用这组自然键来判定「同一个条目」。
class _ItemIndex {
  final List<Map<String, dynamic>> all;
  final Map<String, List<Map<String, dynamic>>> _byKey = {};

  _ItemIndex(this.all, Map<String, String> folderNames) {
    for (final row in all) {
      final folderId = row['folder_id'] as String?;
      final folderName = folderId == null ? '' : (folderNames[folderId] ?? '');
      final key = '${row['type']}|$folderName|${row['name']}';
      _byKey.putIfAbsent(key, () => []).add(row);
    }
  }

  /// 取出一个匹配项并将其移出候选池。
  /// 本地存在同名条目时按出现顺序依次消费，避免多条文件记录都命中同一行。
  Map<String, dynamic>? take(String type, String folder, String name) {
    final bucket = _byKey['$type|$folder|$name'];
    if (bucket == null || bucket.isEmpty) return null;
    return bucket.removeAt(0);
  }
}
