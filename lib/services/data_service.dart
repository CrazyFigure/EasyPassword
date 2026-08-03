/// 数据服务：条目 / 账号 / API Key 的 CRUD、排序、批量操作
/// 密码区(type=password)与 API Key 区(type=apikey)共用一套服务，按 type 物理分离
library;

import 'dart:math';

import '../models/account.dart';
import '../models/api_key.dart';
import '../models/password_item.dart';
import 'crypto_service.dart';
import 'database.dart';

class DataService {
  final CryptoService crypto;
  DataService(this.crypto);

  static const _chars =
      'abcdefghijklmnopqrstuvwxyz0123456789';

  /// 生成唯一短 ID
  static String genId() {
    final r = Random();
    return List.generate(16, (_) => _chars[r.nextInt(_chars.length)]).join();
  }

  // ================= 条目 =================

  /// 查询某类型的所有未删除条目
  Future<List<PasswordItem>> listItems(String type,
      {String? order}) async {
    final rows = await (await DatabaseService.db).query(
      'password_items',
      where: 'type = ? AND deleted = 0',
      whereArgs: [type],
      orderBy: order ?? 'sort_order ASC',
    );
    return rows.map(PasswordItem.fromMap).toList();
  }

  /// 按名称升序排序的列表（需求 3.5.5 默认排序）
  Future<List<PasswordItem>> listItemsByName(String type) async {
    final rows = await (await DatabaseService.db).query(
      'password_items',
      where: 'type = ? AND deleted = 0',
      whereArgs: [type],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return rows.map(PasswordItem.fromMap).toList();
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
    int? sortOrder,
  }) async {
    final db = await DatabaseService.db;
    final now = DateTime.now();
    final order = sortOrder ?? await _nextSortOrder(type);
    final item = PasswordItem(
      id: genId(),
      type: type,
      name: name,
      url: url,
      siteNote: siteNote,
      sortOrder: order,
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('password_items', item.toMap());
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
  }

  Future<int> _nextSortOrder(String type) async {
    final rows = await (await DatabaseService.db).rawQuery(
      'SELECT MAX(sort_order) AS m FROM password_items WHERE type = ? AND deleted = 0',
      [type],
    );
    final m = rows.first['m'] as int? ?? -1;
    return m + 1;
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
    return acc;
  }

  /// 更新账号（密码为空表示不修改）
  Future<void> updateAccount(Account acc, {String? newPassword}) async {
    final db = await DatabaseService.db;
    var updated = acc;
    if (newPassword != null && newPassword.isNotEmpty) {
      updated = updated.copyWith(passwordEnc: await crypto.encrypt(newPassword));
    }
    await db.update(
      'accounts',
      updated.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [acc.id],
    );
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
    return k;
  }

  /// 更新 API Key（key 为空表示不修改）
  Future<void> updateApiKey(ApiKey k, {String? newKey}) async {
    final db = await DatabaseService.db;
    var updated = k;
    if (newKey != null && newKey.isNotEmpty) {
      updated = updated.copyWith(keyEnc: await crypto.encrypt(newKey));
    }
    await db.update(
      'api_keys',
      updated.copyWith(updatedAt: DateTime.now()).toMap(),
      where: 'id = ?',
      whereArgs: [k.id],
    );
  }

  Future<void> deleteApiKey(String id) async {
    final db = await DatabaseService.db;
    await db.rawUpdate(
      'UPDATE api_keys SET deleted = 1, updated_at = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, id],
    );
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
