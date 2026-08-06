/// 数据库迁移测试：覆盖历史结构升级、数据保留与同步触发器刷新。
library;

import 'package:easypassword/services/crypto_service.dart';
import 'package:easypassword/services/data_service.dart';
import 'package:easypassword/services/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 按 v1 的建表语句造一个老库（无 folders 表、password_items 无 folder_id）
Future<void> _createV1Schema(Database db) async {
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

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('v1 老库升级到最新版后原有数据完好且可用文件夹', () async {
    // 用磁盘上的临时库文件，才能先关闭再以新版本重新打开
    final dir = await databaseFactory.getDatabasesPath();
    final path =
        '$dir/migration_test_${DateTime.now().microsecondsSinceEpoch}.db';
    await databaseFactory.deleteDatabase(path);

    // 1) 建 v1 库并写入一条老数据
    final v1 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
          version: 1, onCreate: (db, _) => _createV1Schema(db)),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await v1.insert('password_items', {
      'id': 'old-item-1',
      'type': 'password',
      'name': '老条目',
      'url': 'https://example.com',
      'site_note': '升级前就存在',
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
      'deleted': 0,
    });
    await v1.close();

    // 2) 以应用当前版本重新打开，触发 onUpgrade
    DatabaseService.overridePath = path;
    await DatabaseService.resetForTest();
    final crypto = CryptoService()..setKey(CryptoService().generateDeviceKey());
    final data = DataService(crypto);

    // 老条目仍在根目录且字段完整
    final items = await data.listItems('password');
    expect(items.length, 1);
    expect(items.first.name, '老条目');
    expect(items.first.siteNote, '升级前就存在');
    // 迁移后 folder_id 为 NULL，即留在根目录
    expect(items.first.folderId, isNull);

    // 3) 新的文件夹功能在升级后的库上可用
    final folder = await data.addFolder('password', '升级后新建');
    await data.moveItemsToFolder(['old-item-1'], folder.id);
    expect(await data.listItems('password'), isEmpty);
    final inFolder = await data.listItems('password', folderId: folder.id);
    expect(inFolder.length, 1);
    expect(inFolder.first.name, '老条目');

    // 清理，避免影响其他测试文件共享的静态状态
    await DatabaseService.resetForTest();
    DatabaseService.overridePath = null;
    await databaseFactory.deleteDatabase(path);
  });

  test('v2 老库升级到 v3 后文件夹数据完好且可设颜色', () async {
    final dir = await databaseFactory.getDatabasesPath();
    final path =
        '$dir/migration_v2_${DateTime.now().microsecondsSinceEpoch}.db';
    await databaseFactory.deleteDatabase(path);

    // 1) 建 v2 库（有 folders 表和 folder_id，但没有 color 列）并写入老数据
    final v2 = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await _createV1Schema(db);
          await db
              .execute('ALTER TABLE password_items ADD COLUMN folder_id TEXT');
          await db.execute('''
            CREATE TABLE folders (
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL,
              name TEXT NOT NULL,
              sort_order INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              deleted INTEGER NOT NULL DEFAULT 0
            )
          ''');
        },
      ),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    await v2.insert('folders', {
      'id': 'old-folder-1',
      'type': 'password',
      'name': 'v2 老文件夹',
      'sort_order': 0,
      'created_at': now,
      'updated_at': now,
      'deleted': 0,
    });
    await v2.insert('password_items', {
      'id': 'old-item-2',
      'type': 'password',
      'name': 'v2 老条目',
      'url': '',
      'site_note': '',
      'sort_order': 0,
      'folder_id': 'old-folder-1',
      'created_at': now,
      'updated_at': now,
      'deleted': 0,
    });
    await v2.close();

    // 2) 以当前版本重新打开，触发 v2 → v3 迁移（补 color 列）
    DatabaseService.overridePath = path;
    await DatabaseService.resetForTest();
    final crypto = CryptoService()..setKey(CryptoService().generateDeviceKey());
    final data = DataService(crypto);

    // 老文件夹与其中的条目都完好，color 为 NULL 即沿用默认色
    final folders = await data.listFolders('password');
    expect(folders.length, 1);
    expect(folders.first.name, 'v2 老文件夹');
    expect(folders.first.color, isNull);
    final inFolder = await data.listItems('password', folderId: 'old-folder-1');
    expect(inFolder.length, 1);
    expect(inFolder.first.name, 'v2 老条目');

    // 3) 升级后可给老文件夹设置颜色
    await data.updateFolder(folders.first.copyWith(color: 0xFFE57373));
    expect((await data.listFolders('password')).first.color, 0xFFE57373);

    await DatabaseService.resetForTest();
    DatabaseService.overridePath = null;
    await databaseFactory.deleteDatabase(path);
  });

  test('旧版升级后分区排序与安全键盘设置都会进入同步日志', () async {
    final dir = await databaseFactory.getDatabasesPath();
    final path =
        '$dir/migration_v4_${DateTime.now().microsecondsSinceEpoch}.db';
    await databaseFactory.deleteDatabase(path);

    // 先由当前版本创建完整结构，再还原 v4 的旧设置触发器与版本号。
    DatabaseService.overridePath = path;
    await DatabaseService.resetForTest();
    final v4 = await DatabaseService.db;
    await v4.execute('DROP TRIGGER sync_settings_insert');
    await v4.execute('DROP TRIGGER sync_settings_update');
    await v4.execute('''
      CREATE TRIGGER sync_settings_insert
      AFTER INSERT ON settings
      WHEN NEW.key IN ('sort_mode')
      BEGIN
        INSERT INTO sync_journal(entity_type, entity_id, operation, changed_at)
        VALUES ('settings', NEW.key, 'upsert', NEW.updated_at);
      END
    ''');
    await v4.execute('''
      CREATE TRIGGER sync_settings_update
      AFTER UPDATE ON settings
      WHEN NEW.key IN ('sort_mode')
      BEGIN
        INSERT INTO sync_journal(entity_type, entity_id, operation, changed_at)
        VALUES ('settings', NEW.key, 'upsert', NEW.updated_at);
      END
    ''');
    await v4.setVersion(4);
    await DatabaseService.resetForTest();

    // 重新打开升级到最新版；新增的分区排序与安全键盘键都必须被记录。
    final upgraded = await DatabaseService.db;
    await upgraded.delete('sync_journal');
    await DatabaseService.setSetting('sort_mode_password', 'custom');
    await DatabaseService.setSetting('secure_keyboard_enabled', '0');
    final rows = await upgraded.query(
      'sync_journal',
      where: 'entity_type = ?',
      whereArgs: ['settings'],
    );
    expect(
      rows.map((row) => row['entity_id']).toSet(),
      containsAll({'sort_mode_password', 'secure_keyboard_enabled'}),
    );

    await DatabaseService.resetForTest();
    DatabaseService.overridePath = null;
    await databaseFactory.deleteDatabase(path);
  });
}
