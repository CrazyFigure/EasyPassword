/// 数据服务：条目 / 账号 / API Key 的 CRUD、排序、批量操作
/// 密码区(type=password)与 API Key 区(type=apikey)共用一套服务，按 type 物理分离
library;

import 'dart:async';
import 'dart:math';

import '../core/name_sort.dart';
import '../models/account.dart';
import '../models/api_key.dart';
import '../models/folder.dart';
import '../models/password_item.dart';
import 'crypto_service.dart';
import 'database.dart';

class DataService {
  final CryptoService crypto;
  DataService(this.crypto);

  /// 数据成功落库后的通知入口，由 AppState 接入防抖自动同步。
  /// 回调不阻塞当前保存操作，断网时用户仍可继续编辑，由后续定时任务重试。
  Future<void> Function()? onChanged;

  void _notifyChanged() {
    final callback = onChanged;
    if (callback != null) unawaited(callback());
  }

  /// 供绕过本服务直接写库的批量操作（如明文导入）在事务提交后调用，
  /// 让这类改动同样进入自动同步的防抖队列。
  void notifyChanged() => _notifyChanged();

  static const _chars = 'abcdefghijklmnopqrstuvwxyz0123456789';

  /// 生成唯一短 ID
  static String genId() {
    final r = Random();
    return List.generate(16, (_) => _chars[r.nextInt(_chars.length)]).join();
  }

  // ================= 条目 =================

  /// 查询某类型的条目。
  /// [folderId] 为 null 时返回根目录条目（未归入任何文件夹）；
  /// 传入文件夹 id 则只返回该文件夹内的条目；
  /// [allFolders] 为 true 时忽略文件夹层级，返回该类型全部条目（搜索/导出用）。
  Future<List<PasswordItem>> listItems(String type,
      {String? order, String? folderId, bool allFolders = false}) async {
    final where = StringBuffer('type = ? AND deleted = 0');
    final args = <Object?>[type];
    if (!allFolders) {
      // folder_id 可为 NULL，必须用 IS NULL 而非 = ?
      if (folderId == null) {
        where.write(' AND folder_id IS NULL');
      } else {
        where.write(' AND folder_id = ?');
        args.add(folderId);
      }
    }
    final rows = await (await DatabaseService.db).query(
      'password_items',
      where: where.toString(),
      whereArgs: args,
      orderBy: order ?? 'sort_order ASC',
    );
    return rows.map(PasswordItem.fromMap).toList();
  }

  /// 按名称升序排序的列表（需求 3.5.5 默认排序），文件夹语义同 [listItems]。
  ///
  /// 排序在 Dart 侧完成而不用 SQL 的 COLLATE NOCASE：后者按 UTF-8 码点比较，
  /// 会把汉字整体排到字母之后，且汉字之间不按拼音（规则见 core/name_sort.dart）。
  Future<List<PasswordItem>> listItemsByName(String type,
      {String? folderId, bool allFolders = false}) async {
    final items =
        await listItems(type, folderId: folderId, allFolders: allFolders);
    return sortByName(items, (item) => item.name);
  }

  Future<PasswordItem?> getItem(String id) async {
    final rows = await (await DatabaseService.db).query(
      'password_items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return PasswordItem.fromMap(rows.first);
  }

  /// 新增条目
  Future<PasswordItem> addItem(
    String type,
    String name, {
    String url = '',
    String siteNote = '',
    String? folderId,
    int? sortOrder,
  }) async {
    final db = await DatabaseService.db;
    final now = DateTime.now();
    final order = sortOrder ?? await _nextSortOrder(type, folderId);
    final item = PasswordItem(
      id: genId(),
      type: type,
      name: name,
      url: url,
      siteNote: siteNote,
      folderId: folderId,
      sortOrder: order,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('password_items', item.toMap());
    _notifyChanged();
    return item;
  }

  /// 更新条目（名称/URL/备注）
  Future<void> updateItem(PasswordItem item) async {
    final db = await DatabaseService.db;
    await db.update(
      'password_items',
      item.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
    _notifyChanged();
  }

  /// 软删除条目（连同其账号与 key 一并软删）
  Future<void> deleteItem(String id) async {
    final db = await DatabaseService.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE password_items SET deleted = 1, updated_at = ? WHERE id = ?',
        [now, id],
      );
      // 账号与 api key 级联软删
      final accounts = await txn.query('accounts',
          where: 'item_id = ? AND deleted = 0', whereArgs: [id]);
      for (final a in accounts) {
        await txn.rawUpdate(
          'UPDATE accounts SET deleted = 1, updated_at = ? WHERE id = ?',
          [now, a['id']],
        );
        await txn.rawUpdate(
          'UPDATE api_keys SET deleted = 1, updated_at = ? WHERE account_id = ?',
          [now, a['id']],
        );
      }
    });
    _notifyChanged();
  }

  /// 批量软删除条目（需求 3.4）
  Future<void> deleteItems(List<String> ids) async {
    for (final id in ids) {
      await deleteItem(id);
    }
  }

  /// 拖动排序：保存条目新顺序
  Future<void> reorderItems(List<String> orderedIds) async {
    final db = await DatabaseService.db;
    await db.transaction((txn) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await txn.rawUpdate(
          'UPDATE password_items SET sort_order = ?, updated_at = ? WHERE id = ?',
          [i, DateTime.now().millisecondsSinceEpoch, orderedIds[i]],
        );
      }
    });
    _notifyChanged();
  }

  /// 同一层级内的下一个排序号。
  /// 文件夹内按该文件夹单独计数；根目录则与文件夹共用序号（见 [_nextRootOrder]）。
  Future<int> _nextSortOrder(String type, String? folderId) async {
    if (folderId == null) return _nextRootOrder(type);
    final rows = await (await DatabaseService.db).rawQuery(
      'SELECT MAX(sort_order) AS m FROM password_items '
      'WHERE type = ? AND deleted = 0 AND folder_id = ?',
      [type, folderId],
    );
    final m = rows.first['m'] as int? ?? -1;
    return m + 1;
  }

  // ================= 文件夹 =================

  /// 某类型下的全部文件夹（按排序号）
  Future<List<Folder>> listFolders(String type, {String? order}) async {
    final rows = await (await DatabaseService.db).query(
      'folders',
      where: 'type = ? AND deleted = 0',
      whereArgs: [type],
      orderBy: order ?? 'sort_order ASC',
    );
    return rows.map(Folder.fromMap).toList();
  }

  /// 按名称升序的文件夹列表（与条目共用 [compareNames] 规则）
  Future<List<Folder>> listFoldersByName(String type) async {
    final folders = await listFolders(type);
    return sortByName(folders, (folder) => folder.name);
  }

  Future<Folder?> getFolder(String id) async {
    final rows = await (await DatabaseService.db).query(
      'folders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Folder.fromMap(rows.first);
  }

  /// 新增文件夹
  Future<Folder> addFolder(String type, String name, {int? color}) async {
    final db = await DatabaseService.db;
    final now = DateTime.now();
    final folder = Folder(
      id: genId(),
      type: type,
      name: name,
      color: color,
      // 与根目录条目共用同一套排序号，保证自定义排序时能交叉排列
      sortOrder: await _nextRootOrder(type),
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('folders', folder.toMap());
    _notifyChanged();
    return folder;
  }

  /// 重命名 / 更新文件夹
  Future<void> updateFolder(Folder folder) async {
    final db = await DatabaseService.db;
    await db.update(
      'folders',
      folder.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [folder.id],
    );
    _notifyChanged();
  }

  /// 软删除文件夹。
  /// [deleteContents] 为 true 时连同文件夹内条目一并删除；
  /// 否则把内部条目移回根目录，避免数据"消失"在已删除的文件夹里。
  Future<void> deleteFolder(String id, {bool deleteContents = false}) async {
    final db = await DatabaseService.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final inside = await db.query(
      'password_items',
      columns: ['id'],
      where: 'folder_id = ? AND deleted = 0',
      whereArgs: [id],
    );
    if (deleteContents) {
      // 复用条目删除逻辑，保证账号与 api key 级联软删
      for (final row in inside) {
        await deleteItem(row['id'] as String);
      }
    } else {
      await db.rawUpdate(
        'UPDATE password_items SET folder_id = NULL, updated_at = ? '
        'WHERE folder_id = ? AND deleted = 0',
        [now, id],
      );
    }
    await db.rawUpdate(
      'UPDATE folders SET deleted = 1, updated_at = ? WHERE id = ?',
      [now, id],
    );
    _notifyChanged();
  }

  /// 把条目移动到指定文件夹；[folderId] 为 null 表示移出到根目录
  Future<void> moveItemsToFolder(List<String> itemIds, String? folderId) async {
    if (itemIds.isEmpty) return;
    final db = await DatabaseService.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final id in itemIds) {
        await txn.update(
          'password_items',
          {'folder_id': folderId, 'updated_at': now},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
    _notifyChanged();
  }

  /// 根列表混合拖动排序：文件夹与条目共用一套序号，可任意交叉排列。
  /// [entries] 按最终显示顺序传入，元素形如 ('folder'|'item', id)。
  Future<void> reorderRootEntries(
      List<(String kind, String id)> entries) async {
    final db = await DatabaseService.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (var i = 0; i < entries.length; i++) {
        final (kind, id) = entries[i];
        // 文件夹与条目分表存储，但序号取自同一个连续序列
        final table = kind == 'folder' ? 'folders' : 'password_items';
        await txn.rawUpdate(
          'UPDATE $table SET sort_order = ?, updated_at = ? WHERE id = ?',
          [i, now, id],
        );
      }
    });
    _notifyChanged();
  }

  /// 统计文件夹内条目数（列表上展示"N 项"）
  Future<Map<String, int>> countItemsByFolder(String type) async {
    final rows = await (await DatabaseService.db).rawQuery(
      'SELECT folder_id, COUNT(*) AS c FROM password_items '
      'WHERE type = ? AND deleted = 0 AND folder_id IS NOT NULL '
      'GROUP BY folder_id',
      [type],
    );
    return {
      for (final r in rows) r['folder_id'] as String: (r['c'] as int?) ?? 0,
    };
  }

  /// 根层级的下一个排序号：取「根目录条目」与「文件夹」两张表的最大值 +1。
  /// 两者共用一套序号，新建的行才能稳定排在末尾而不与已有行重号。
  Future<int> _nextRootOrder(String type) async {
    final db = await DatabaseService.db;
    final itemRows = await db.rawQuery(
      'SELECT MAX(sort_order) AS m FROM password_items '
      'WHERE type = ? AND deleted = 0 AND folder_id IS NULL',
      [type],
    );
    final folderRows = await db.rawQuery(
      'SELECT MAX(sort_order) AS m FROM folders WHERE type = ? AND deleted = 0',
      [type],
    );
    final maxItem = (itemRows.first['m'] as int?) ?? -1;
    final maxFolder = (folderRows.first['m'] as int?) ?? -1;
    return (maxItem > maxFolder ? maxItem : maxFolder) + 1;
  }

  // ================= 账号 =================

  Future<List<Account>> listAccounts(String itemId) async {
    final rows = await (await DatabaseService.db).query(
      'accounts',
      where: 'item_id = ? AND deleted = 0',
      whereArgs: [itemId],
      orderBy: 'sort_order ASC',
    );
    return rows.map(Account.fromMap).toList();
  }

  Future<Account?> getAccount(String id) async {
    final rows = await (await DatabaseService.db).query(
      'accounts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Account.fromMap(rows.first);
  }

  /// 新增账号（密码加密后入库）
  Future<Account> addAccount(
    String itemId,
    String username,
    String passwordPlain, {
    String note = '',
    int? sortOrder,
  }) async {
    final db = await DatabaseService.db;
    final now = DateTime.now();
    final order = sortOrder ?? await _nextAccountOrder(itemId);
    final enc = await crypto.encrypt(passwordPlain);
    final acc = Account(
      id: genId(),
      itemId: itemId,
      username: username,
      passwordEnc: enc,
      note: note,
      sortOrder: order,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('accounts', acc.toMap());
    _notifyChanged();
    return acc;
  }

  /// 更新账号。
  ///
  /// [newPassword] 为 null 表示保留原密码；传入空串表示用户主动清空密码，
  /// 此时必须真的写入空值——把空串折叠成"不修改"会让清空操作静默失效。
  Future<void> updateAccount(Account acc, {String? newPassword}) async {
    final db = await DatabaseService.db;
    var updated = acc;
    if (newPassword != null) {
      // 空串不进加密：密文空值直接落库，解密侧对空串本就返回空串
      updated = updated.copyWith(
        passwordEnc:
            newPassword.isEmpty ? '' : await crypto.encrypt(newPassword),
      );
    }
    await db.update(
      'accounts',
      updated.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [acc.id],
    );
    _notifyChanged();
  }

  Future<void> deleteAccount(String id) async {
    final db = await DatabaseService.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE accounts SET deleted = 1, updated_at = ? WHERE id = ?',
        [now, id],
      );
      await txn.rawUpdate(
        'UPDATE api_keys SET deleted = 1, updated_at = ? WHERE account_id = ?',
        [now, id],
      );
    });
    _notifyChanged();
  }

  /// 账号内拖动排序
  Future<void> reorderAccounts(List<String> orderedIds) async {
    final db = await DatabaseService.db;
    await db.transaction((txn) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await txn.rawUpdate(
          'UPDATE accounts SET sort_order = ?, updated_at = ? WHERE id = ?',
          [i, DateTime.now().millisecondsSinceEpoch, orderedIds[i]],
        );
      }
    });
    _notifyChanged();
  }

  Future<int> _nextAccountOrder(String itemId) async {
    final rows = await (await DatabaseService.db).rawQuery(
      'SELECT MAX(sort_order) AS m FROM accounts WHERE item_id = ? AND deleted = 0',
      [itemId],
    );
    final m = rows.first['m'] as int? ?? -1;
    return m + 1;
  }

  // ================= API Key =================

  Future<List<ApiKey>> listApiKeys(String accountId) async {
    final rows = await (await DatabaseService.db).query(
      'api_keys',
      where: 'account_id = ? AND deleted = 0',
      whereArgs: [accountId],
      orderBy: 'sort_order ASC',
    );
    return rows.map(ApiKey.fromMap).toList();
  }

  /// 新增 API Key（加密后入库）
  Future<ApiKey> addApiKey(
    String accountId,
    String keyPlain, {
    String note = '',
    int? sortOrder,
  }) async {
    final db = await DatabaseService.db;
    final now = DateTime.now();
    final order = sortOrder ?? await _nextKeyOrder(accountId);
    final enc = await crypto.encrypt(keyPlain);
    final k = ApiKey(
      id: genId(),
      accountId: accountId,
      keyEnc: enc,
      note: note,
      sortOrder: order,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('api_keys', k.toMap());
    _notifyChanged();
    return k;
  }

  /// 更新 API Key。
  ///
  /// [newKey] 为 null 表示保留原 key；传入空串表示用户主动清空，语义同
  /// [updateAccount] 的 newPassword。
  Future<void> updateApiKey(ApiKey k, {String? newKey}) async {
    final db = await DatabaseService.db;
    var updated = k;
    if (newKey != null) {
      updated = updated.copyWith(
        keyEnc: newKey.isEmpty ? '' : await crypto.encrypt(newKey),
      );
    }
    await db.update(
      'api_keys',
      updated.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [k.id],
    );
    _notifyChanged();
  }

  Future<void> deleteApiKey(String id) async {
    final db = await DatabaseService.db;
    await db.rawUpdate(
      'UPDATE api_keys SET deleted = 1, updated_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
    _notifyChanged();
  }

  /// 账号内 API Key 拖动排序
  Future<void> reorderApiKeys(List<String> orderedIds) async {
    final db = await DatabaseService.db;
    await db.transaction((txn) async {
      for (var i = 0; i < orderedIds.length; i++) {
        await txn.rawUpdate(
          'UPDATE api_keys SET sort_order = ?, updated_at = ? WHERE id = ?',
          [i, DateTime.now().millisecondsSinceEpoch, orderedIds[i]],
        );
      }
    });
    _notifyChanged();
  }

  Future<int> _nextKeyOrder(String accountId) async {
    final rows = await (await DatabaseService.db).rawQuery(
      'SELECT MAX(sort_order) AS m FROM api_keys WHERE account_id = ? AND deleted = 0',
      [accountId],
    );
    final m = rows.first['m'] as int? ?? -1;
    return m + 1;
  }

  // ================= 明文解密辅助 =================

  /// 解密账号密码（容错）
  Future<String> plainPassword(Account acc) => crypto.decrypt(acc.passwordEnc);

  /// 解密 API Key（容错）
  Future<String> plainKey(ApiKey k) => crypto.decrypt(k.keyEnc);
}
