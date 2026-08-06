/// 数据库服务：SQLite 建库与基础访问
/// Android 用 sqflite，Windows 用 sqflite_common_ffi，API 一致
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  static Database? _db;
  // v2：新增 folders 表与 password_items.folder_id（文件夹分组）
  // v3：folders 新增 color 列（文件夹自定义颜色）
  // v4：设置补修改时间，并用同步日志持久记录离线期间的每次数据变更
  // v5：排序设置按密码/API Key 分区，并刷新设置同步触发器的键范围
  // v6：安全键盘偏好加入跨设备设置，并再次刷新设置同步触发器
  static const int _version = 6;

  /// 可跨设备同步的系统设置。WebDAV 凭据、设备数据密钥和同步运行状态
  /// 必须留在本机，避免远端配置覆盖后导致设备失去访问能力。
  static const Set<String> syncableSettingKeys = {
    'font_scale',
    'tab_visibility',
    // 保留旧键用于接收旧设备快照；两个新键分别同步各分区的排序规则。
    'sort_mode',
    'sort_mode_password',
    'sort_mode_apikey',
    'reveal_all',
    'secure_keyboard_enabled',
    'app_lock_enabled',
    'app_lock_pin_hash',
    'app_lock_salt',
    'security_question',
    'security_answer_hash',
  };

  /// 测试时可注入内存数据库路径（如 sqflite_common_ffi 的 inMemoryDatabasePath）
  @visibleForTesting
  static String? overridePath;

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    // Windows/桌面端初始化 FFI 工厂
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final path = overridePath ?? await _defaultDbPath();
    return databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _version,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  static Future<String> _defaultDbPath() async {
    final dir = await getApplicationSupportDirectory();
    return p.join(dir.path, 'easypassword.db');
  }

  /// 测试重置：关闭已打开的库并清空路径覆盖
  @visibleForTesting
  static Future<void> resetForTest() async {
    await _db?.close();
    _db = null;
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE password_items (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        url TEXT DEFAULT '',
        site_note TEXT DEFAULT '',
        folder_id TEXT,
        sort_order INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE accounts (
        id TEXT PRIMARY KEY,
        item_id TEXT NOT NULL,
        username TEXT DEFAULT '',
        password_enc TEXT DEFAULT '',
        note TEXT DEFAULT '',
        sort_order INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE api_keys (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        key_enc TEXT DEFAULT '',
        note TEXT DEFAULT '',
        sort_order INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_accounts_item ON accounts(item_id)');
    await db.execute('CREATE INDEX idx_keys_account ON api_keys(account_id)');
    await db.execute('CREATE INDEX idx_items_type ON password_items(type)');
    await _createFolderSchema(db);
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT DEFAULT '',
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await _createSyncJournalSchema(db);
  }

  /// 文件夹表与相关索引（v2 新增，建库与升级共用）
  static Future<void> _createFolderSchema(Database db) async {
    await db.execute('''
      CREATE TABLE folders (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        name TEXT NOT NULL,
        color INTEGER,
        sort_order INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX idx_folders_type ON folders(type)');
    await db
        .execute('CREATE INDEX idx_items_folder ON password_items(folder_id)');
  }

  /// 版本迁移：
  /// v1 → v2：补齐 folders 表与 password_items.folder_id 列，已有数据
  ///          folder_id 保持 NULL（全部落在根目录），不影响现有条目。
  /// v2 → v3：folders 补 color 列，NULL 表示沿用主题默认色；
  /// v3 → v4：设置补修改时间，并建立同步变更日志与自动记录触发器；
  /// v4 → v5：刷新设置触发器，使两个分区排序键都能记录同步日志；
  /// v5 → v6：刷新设置触发器，使安全键盘偏好也能记录同步日志。
  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE password_items ADD COLUMN folder_id TEXT');
      // v2 的建表语句此时已含 color 列，无需再执行 v3 的 ALTER
      await _createFolderSchema(db);
    }
    if (oldVersion >= 2 && oldVersion < 3) {
      await db.execute('ALTER TABLE folders ADD COLUMN color INTEGER');
    }
    if (oldVersion < 4) {
      await db.execute(
          'ALTER TABLE settings ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0');
      await _createSyncJournalSchema(db);
    }
    if (oldVersion >= 4 && oldVersion < 6) {
      await _recreateSyncSettingTriggers(db);
    }
  }

  /// 建立轻量同步日志。业务表保留当前状态与删除墓碑，日志只负责标记
  /// “本地还有未推送变更”，成功同步后即可安全清空，不会无限增长。
  static Future<void> _createSyncJournalSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_journal (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        changed_at INTEGER NOT NULL
      )
    ''');
    for (final table in const [
      'folders',
      'password_items',
      'accounts',
      'api_keys',
    ]) {
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS sync_${table}_insert
        AFTER INSERT ON $table
        BEGIN
          INSERT INTO sync_journal(entity_type, entity_id, operation, changed_at)
          VALUES ('$table', NEW.id,
            CASE WHEN NEW.deleted = 1 THEN 'delete' ELSE 'upsert' END,
            NEW.updated_at);
        END
      ''');
      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS sync_${table}_update
        AFTER UPDATE ON $table
        BEGIN
          INSERT INTO sync_journal(entity_type, entity_id, operation, changed_at)
          VALUES ('$table', NEW.id,
            CASE WHEN NEW.deleted = 1 THEN 'delete' ELSE 'upsert' END,
            NEW.updated_at);
        END
      ''');
    }
    await _recreateSyncSettingTriggers(db);
  }

  /// 重建设置同步触发器。SQLite 的 CREATE TRIGGER IF NOT EXISTS 不会更新
  /// 既有 WHEN 条件，因此新增可同步设置键时必须先删除旧触发器再创建。
  static Future<void> _recreateSyncSettingTriggers(Database db) async {
    await db.execute('DROP TRIGGER IF EXISTS sync_settings_insert');
    await db.execute('DROP TRIGGER IF EXISTS sync_settings_update');
    final settingKeys = syncableSettingKeys.map((key) => "'$key'").join(',');
    await db.execute('''
      CREATE TRIGGER sync_settings_insert
      AFTER INSERT ON settings
      WHEN NEW.key IN ($settingKeys)
      BEGIN
        INSERT INTO sync_journal(entity_type, entity_id, operation, changed_at)
        VALUES ('settings', NEW.key, 'upsert', NEW.updated_at);
      END
    ''');
    await db.execute('''
      CREATE TRIGGER sync_settings_update
      AFTER UPDATE ON settings
      WHEN NEW.key IN ($settingKeys)
      BEGIN
        INSERT INTO sync_journal(entity_type, entity_id, operation, changed_at)
        VALUES ('settings', NEW.key, 'upsert', NEW.updated_at);
      END
    ''');
  }

  /// 读取单值设置
  static Future<String?> getSetting(String key) async {
    final database = await db;
    final rows =
        await database.query('settings', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// 写入设置并记录墙钟修改时间，供多端按“最后修改者胜”合并。
  /// 同一次批量设置可显式传入 [updatedAt]，保证相关字段使用一致时间。
  static Future<void> setSetting(String key, String value,
      {int? updatedAt}) async {
    final database = await db;
    await database.insert(
      'settings',
      {
        'key': key,
        'value': value,
        'updated_at': updatedAt ?? DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 读取全部可同步设置行，保留每项独立修改时间用于冲突裁决。
  static Future<List<Map<String, dynamic>>> getSyncableSettingRows() async {
    final database = await db;
    final placeholders = List.filled(syncableSettingKeys.length, '?').join(',');
    return database.query(
      'settings',
      where: 'key IN ($placeholders)',
      whereArgs: syncableSettingKeys.toList(),
    );
  }

  /// 获取当前日志水位。同步开始后新增的记录高于该值，成功回写远端时不会
  /// 被误清理，并会在下一轮自动同步继续推送。
  static Future<int> getSyncJournalHighWaterMark() async {
    final database = await db;
    final rows =
        await database.rawQuery('SELECT MAX(id) AS max_id FROM sync_journal');
    return (rows.first['max_id'] as int?) ?? 0;
  }

  /// 清理指定水位及之前已成功写入远端的日志；数据与删除墓碑不受影响。
  static Future<void> clearSyncJournalThrough(int highWaterMark) async {
    if (highWaterMark <= 0) return;
    final database = await db;
    await database.delete(
      'sync_journal',
      where: 'id <= ?',
      whereArgs: [highWaterMark],
    );
  }

  /// 是否存在尚未成功推送的本地修改，供恢复联网和定时任务判断。
  static Future<bool> hasPendingSyncChanges() async {
    final rows =
        await (await db).rawQuery('SELECT 1 FROM sync_journal LIMIT 1');
    return rows.isNotEmpty;
  }

  /// 批量读取设置（同步用）
  static Future<Map<String, String>> getAllSettings() async {
    final database = await db;
    final rows = await database.query('settings');
    return {
      for (final r in rows) r['key'] as String: (r['value'] as String?) ?? '',
    };
  }

  /// 重置全部设置（恢复默认）
  static Future<void> clearSettings() async {
    final database = await db;
    await database.delete('settings');
  }
}
