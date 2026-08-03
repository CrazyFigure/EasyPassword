/// WebDAV 同步快照与合并单元测试（本地逻辑，不依赖网络）
library;

import 'package:easypassword/services/crypto_service.dart';
import 'package:easypassword/services/data_service.dart';
import 'package:easypassword/services/database.dart';
import 'package:easypassword/services/webdav_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    DatabaseService.overridePath = inMemoryDatabasePath;
  });

  late CryptoService crypto;
  late DataService data;
  late WebDavService webdav;

  setUp(() async {
    crypto = CryptoService();
    crypto.setKey(crypto.generateDeviceKey());
    data = DataService(crypto);
    webdav = WebDavService(crypto, data);
    final db = await DatabaseService.db;
    await db.delete('api_keys');
    await db.delete('accounts');
    await db.delete('password_items');
  });

  test('加密快照不包含明文', () async {
    final item = await data.addItem('password', 'Google');
    await data.addAccount(item.id, 'user@gmail.com', 'TopSecret123');

    final snapshot = await webdav.buildSnapshot();
    expect(snapshot, isNot(contains('TopSecret123')));
    expect(snapshot, isNot(contains('user@gmail.com')));
  });

  test('快照可恢复全部数据（跨设备恢复）', () async {
    // 设备 A：写入数据并生成快照
    final item = await data.addItem('apikey', 'OpenAI',
        url: 'https://platform.openai.com', siteNote: 'API 平台');
    final acc = await data.addAccount(item.id, 'admin@openai.com', 'pwd123');
    await data.addApiKey(acc.id, 'sk-proj-xyz', note: '生产');

    final snapshot = await webdav.buildSnapshot();

    // 设备 B：清空本地数据后合并快照
    final db = await DatabaseService.db;
    await db.delete('api_keys');
    await db.delete('accounts');
    await db.delete('password_items');

    final merged = await webdav.mergeSnapshot(snapshot);
    expect(merged, 1);

    final items = await data.listItems('apikey');
    expect(items.length, 1);
    expect(items.first.name, 'OpenAI');
    expect(items.first.siteNote, 'API 平台');

    final accounts = await data.listAccounts(items.first.id);
    expect(accounts.length, 1);
    expect(accounts.first.username, 'admin@openai.com');
    expect(await data.plainPassword(accounts.first), 'pwd123');

    final keys = await data.listApiKeys(accounts.first.id);
    expect(keys.length, 1);
    expect(await data.plainKey(keys.first), 'sk-proj-xyz');
  });
}
