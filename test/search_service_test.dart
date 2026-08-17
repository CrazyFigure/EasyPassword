/// 全局搜索服务单元测试
library;

import 'package:easypassword/services/crypto_service.dart';
import 'package:easypassword/services/data_service.dart';
import 'package:easypassword/services/database.dart';
import 'package:easypassword/services/search_service.dart';
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
  late SearchService search;

  setUp(() async {
    crypto = CryptoService();
    crypto.setKey(crypto.generateDeviceKey());
    data = DataService(crypto);
    search = SearchService(data, crypto);
    final db = await DatabaseService.db;
    await db.delete('api_keys');
    await db.delete('accounts');
    await db.delete('password_items');
    await db.delete('folders');
  });

  test('搜索名称与备注', () async {
    await data.addItem('password', 'Google',
        url: 'https://google.com', siteNote: '主力邮箱');

    final byName = await search.search('google');
    expect(byName.any((r) => r.hitField == '名称'), isTrue);

    final byNote = await search.search('主力邮箱');
    expect(byNote.any((r) => r.hitField == '网站级备注'), isTrue);
  });

  test('搜索用户名、密码（解密后匹配）、API Key', () async {
    final item = await data.addItem('apikey', 'OpenAI');
    final acc =
        await data.addAccount(item.id, 'admin@openai.com', 'OpenSecret');
    await data.addApiKey(acc.id, 'sk-proj-AIKEY123', note: '生产环境');

    // 用户名
    final byUser = await search.search('admin@openai');
    expect(byUser.any((r) => r.hitField == '用户名'), isTrue);

    // 密码（密文内匹配）
    final byPwd = await search.search('OpenSecret');
    expect(byPwd.any((r) => r.hitField == '密码'), isTrue);

    // API Key 值
    final byKey = await search.search('AIKEY123');
    expect(byKey.any((r) => r.hitField == 'API Key'), isTrue);

    // API Key 备注
    final byKeyNote = await search.search('生产环境');
    expect(byKeyNote.any((r) => r.hitField == 'API Key 备注'), isTrue);
  });

  test('分区筛选：密码区搜索不到 API Key 区数据', () async {
    await data.addItem('apikey', 'OpenAI');
    await data.addItem('password', 'Google');

    final inPassword = await search.search('openai', scope: 'password');
    expect(inPassword, isEmpty);

    final inApikey = await search.search('openai', scope: 'apikey');
    expect(inApikey, isNotEmpty);
  });

  test('文件夹内的搜索结果携带所属目录名，根目录结果不展示目录', () async {
    final folder = await data.addFolder('password', '工作账号');
    await data.addItem('password', '公司邮箱', folderId: folder.id);
    await data.addItem('password', '私人邮箱');

    final inFolder = await search.search('公司邮箱');
    final atRoot = await search.search('私人邮箱');

    expect(inFolder.single.folderName, '工作账号');
    expect(atRoot.single.folderName, isNull);
  });
}
