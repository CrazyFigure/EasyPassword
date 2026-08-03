/// 数据库服务：SQLite 建库与基础访问
/// Android 用 sqflite，Windows 用 sqflite_common_ffi，API 一致
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class DatabaseService {
  static Database? _db;
  static const int _version = 1;

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
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
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
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT DEFAULT ''
      )
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

  /// 写入设置
  static Future<void> setSetting(String key, String value) async {
    final database = await db;
    await database.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
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
