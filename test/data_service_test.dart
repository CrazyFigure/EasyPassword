/// 数据服务单元测试（使用内存数据库）
library;

import 'package:easypassword/services/crypto_service.dart';
import 'package:easypassword/services/data_service.dart';
import 'package:easypassword/services/database.dart';
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

  setUp(() async {
    crypto = CryptoService();
    crypto.setKey(crypto.generateDeviceKey());
    data = DataService(crypto);
    // 清理表数据，保证测试独立
    final db = await DatabaseService.db;
    await db.delete('api_keys');
    await db.delete('accounts');
    await db.delete('password_items');
  });

  test('新增并查询密码条目', () async {
    final item = await data.addItem('password', 'Google',
        url: 'https://google.com', siteNote: '主力邮箱');
    expect(item.name, 'Google');

    final list = await data.listItems('password');
    expect(list.length, 1);
    expect(list.first.siteNote, '主力邮箱');
  });

  test('密码字段加密存储且可解密', () async {
    final item = await data.addItem('password', 'GitHub');
    final acc = await data.addAccount(item.id, 'devuser', 'P@ssw0rd!',
        note: '个人账号');

    // 数据库中的 password_enc 不含明文
    final db = await DatabaseService.db;
    final rows = await db.query('accounts',
        where: 'id = ?', whereArgs: [acc.id], limit: 1);
    final enc = rows.first['password_enc'] as String;
    expect(enc, isNot(contains('P@ssw0rd!')));

    // 通过服务解密
    final plain = await data.plainPassword(acc);
    expect(plain, 'P@ssw0rd!');
  });

  test('API Key 三级结构与加密', () async {
    final item = await data.addItem('apikey', 'OpenAI');
    final acc = await data.addAccount(item.id, 'admin@openai.com', 'pwd');
    await data.addApiKey(acc.id, 'sk-proj-abc123', note: '生产环境');

    final keys = await data.listApiKeys(acc.id);
    expect(keys.length, 1);
    expect(await data.plainKey(keys.first), 'sk-proj-abc123');
  });

  test('拖动排序：条目与账号', () async {
    final a = await data.addItem('password', 'Apple');
    final b = await data.addItem('password', 'AWS');
    final c = await data.addItem('password', 'Google');

    await data.reorderItems([b.id, a.id, c.id]);
    final list = await data.listItems('password');
    expect(list[0].name, 'AWS');
    expect(list[1].name, 'Apple');
    expect(list[2].name, 'Google');

    // 账号排序
    final acc1 = await data.addAccount(a.id, 'u1', 'p1');
    final acc2 = await data.addAccount(a.id, 'u2', 'p2');
    await data.reorderAccounts([acc2.id, acc1.id]);
    final accounts = await data.listAccounts(a.id);
    expect(accounts[0].username, 'u2');
  });

  test('软删除条目级联删除账号与 Key', () async {
    final item = await data.addItem('apikey', 'OpenAI');
    final acc = await data.addAccount(item.id, 'u1', 'p1');
    await data.addApiKey(acc.id, 'sk-1');

    await data.deleteItem(item.id);

    expect(await data.listItems('apikey'), isEmpty);
    // 账号与 Key 软删后不再出现在列表中
    final list = await data.listItems('apikey');
    expect(list, isEmpty);
  });

  test('名称升序排序（不区分大小写）', () async {
    await data.addItem('password', 'Zebra');
    await data.addItem('password', 'Apple');
    await data.addItem('password', 'banana');

    final list = await data.listItemsByName('password');
    expect(list[0].name, 'Apple');
    expect(list[1].name, 'banana');
    expect(list[2].name, 'Zebra');
  });
}
