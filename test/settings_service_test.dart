/// 设置服务单元测试：验证密码/API Key 排序规则独立保存与旧配置兼容。
library;

import 'package:easypassword/core/constants.dart';
import 'package:easypassword/services/database.dart';
import 'package:easypassword/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseService.overridePath = inMemoryDatabasePath;
  });

  setUp(() async {
    final db = await DatabaseService.db;
    await db.delete('settings');
    await db.delete('sync_journal');
  });

  tearDownAll(() async {
    await DatabaseService.resetForTest();
    DatabaseService.overridePath = null;
  });

  test('旧版共用排序规则可作为两个分区的升级回退值', () async {
    await DatabaseService.setSetting(DbKeys.sortMode, 'custom');
    final settings = SettingsService();

    expect(await settings.getSortMode(ItemType.password), 'custom');
    expect(await settings.getSortMode(ItemType.apikey), 'custom');
  });

  test('密码和 API Key 可以保存不同排序规则', () async {
    final settings = SettingsService();

    await settings.setSortMode(ItemType.password, 'custom');
    await settings.setSortMode(ItemType.apikey, 'name_asc');

    expect(await settings.getSortMode(ItemType.password), 'custom');
    expect(await settings.getSortMode(ItemType.apikey), 'name_asc');
    expect(
      await DatabaseService.getSetting(DbKeys.passwordSortMode),
      'custom',
    );
    expect(
      await DatabaseService.getSetting(DbKeys.apikeySortMode),
      'name_asc',
    );
  });

  test('两个分区排序变更都会写入同步日志', () async {
    final settings = SettingsService();

    await settings.setSortMode(ItemType.password, 'custom');
    await settings.setSortMode(ItemType.apikey, 'custom');

    final db = await DatabaseService.db;
    final rows = await db.query(
      'sync_journal',
      where: 'entity_type = ?',
      whereArgs: ['settings'],
    );
    expect(
      rows.map((row) => row['entity_id']).toSet(),
      containsAll({DbKeys.passwordSortMode, DbKeys.apikeySortMode}),
    );
  });
}
