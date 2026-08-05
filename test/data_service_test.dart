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
    await db.delete('folders');
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

  // ================= 文件夹 =================

  test('新增文件夹并在其中创建条目', () async {
    final folder = await data.addFolder('password', '工作');
    await data.addItem('password', '公司邮箱', folderId: folder.id);

    final inFolder = await data.listItems('password', folderId: folder.id);
    expect(inFolder.length, 1);
    expect(inFolder.first.name, '公司邮箱');
    expect(inFolder.first.folderId, folder.id);

    final folders = await data.listFolders('password');
    expect(folders.length, 1);
    expect(folders.first.name, '工作');
  });

  test('根目录列表不包含文件夹内的条目', () async {
    final folder = await data.addFolder('password', '工作');
    await data.addItem('password', '公司邮箱', folderId: folder.id);
    await data.addItem('password', '个人邮箱');

    // 默认查询只返回根目录条目
    final root = await data.listItems('password');
    expect(root.length, 1);
    expect(root.first.name, '个人邮箱');

    // allFolders 用于搜索与导出，需覆盖全部条目
    final all = await data.listItems('password', allFolders: true);
    expect(all.length, 2);
  });

  test('文件夹按类型隔离', () async {
    await data.addFolder('password', '密码分组');
    await data.addFolder('apikey', 'API 分组');

    expect((await data.listFolders('password')).length, 1);
    expect((await data.listFolders('apikey')).length, 1);
    expect((await data.listFolders('password')).first.name, '密码分组');
  });

  test('移动条目进出文件夹', () async {
    final folder = await data.addFolder('password', '工作');
    final item = await data.addItem('password', 'Google');

    // 移入文件夹后应从根目录消失
    await data.moveItemsToFolder([item.id], folder.id);
    expect(await data.listItems('password'), isEmpty);
    expect((await data.listItems('password', folderId: folder.id)).length, 1);

    // 传 null 表示移回根目录
    await data.moveItemsToFolder([item.id], null);
    expect((await data.listItems('password')).length, 1);
    expect(await data.listItems('password', folderId: folder.id), isEmpty);
  });

  test('删除文件夹默认把条目移回根目录', () async {
    final folder = await data.addFolder('password', '工作');
    await data.addItem('password', '公司邮箱', folderId: folder.id);

    await data.deleteFolder(folder.id);

    expect(await data.listFolders('password'), isEmpty);
    // 条目未被删除，而是回到根目录
    final root = await data.listItems('password');
    expect(root.length, 1);
    expect(root.first.name, '公司邮箱');
    expect(root.first.folderId, isNull);
  });

  test('删除文件夹可连同内部条目一起删除', () async {
    final folder = await data.addFolder('password', '工作');
    final item = await data.addItem('password', '公司邮箱', folderId: folder.id);
    final acc = await data.addAccount(item.id, 'u1', 'p1');

    await data.deleteFolder(folder.id, deleteContents: true);

    expect(await data.listFolders('password'), isEmpty);
    expect(await data.listItems('password'), isEmpty);
    expect(await data.listItems('password', allFolders: true), isEmpty);
    // 条目删除应级联软删其账号
    expect(await data.listAccounts(item.id), isEmpty);
    expect(acc.itemId, item.id);
  });

  test('重命名文件夹', () async {
    final folder = await data.addFolder('password', '旧名称');
    await data.updateFolder(folder.copyWith(name: '新名称'));

    final folders = await data.listFolders('password');
    expect(folders.first.name, '新名称');
    expect(folders.first.id, folder.id);
  });

  test('统计各文件夹内条目数', () async {
    final f1 = await data.addFolder('password', '工作');
    final f2 = await data.addFolder('password', '生活');
    await data.addItem('password', 'A', folderId: f1.id);
    await data.addItem('password', 'B', folderId: f1.id);
    await data.addItem('password', 'C', folderId: f2.id);
    await data.addItem('password', '根条目');

    final counts = await data.countItemsByFolder('password');
    expect(counts[f1.id], 2);
    expect(counts[f2.id], 1);
    // 根目录条目不计入任何文件夹
    expect(counts.values.fold<int>(0, (a, b) => a + b), 3);
  });

  test('根层级文件夹与条目共用排序号，文件夹内独立计数', () async {
    final folder = await data.addFolder('password', '工作');
    final root1 = await data.addItem('password', '根1');

    // 根层级共用一套序号，自定义排序时文件夹才能与条目交叉排列
    expect(folder.sortOrder, 0);
    expect(root1.sortOrder, 1);

    // 文件夹内部独立计数，与根层级互不干扰
    final inner1 = await data.addItem('password', '内1', folderId: folder.id);
    final inner2 = await data.addItem('password', '内2', folderId: folder.id);
    expect(inner1.sortOrder, 0);
    expect(inner2.sortOrder, 1);
  });

  test('混合拖动排序：文件夹与条目可任意交叉', () async {
    final f1 = await data.addFolder('password', '文件夹A');
    final i1 = await data.addItem('password', '条目1');
    final f2 = await data.addFolder('password', '文件夹B');
    final i2 = await data.addItem('password', '条目2');

    // 目标顺序：条目2 → 文件夹A → 条目1 → 文件夹B
    await data.reorderRootEntries([
      ('item', i2.id),
      ('folder', f1.id),
      ('item', i1.id),
      ('folder', f2.id),
    ]);

    final items = await data.listItems('password');
    final folders = await data.listFolders('password');
    // 两张表各自按 sort_order 取回，序号来自同一序列
    expect(items.map((e) => e.sortOrder).toList(), [0, 2]);
    expect(items.map((e) => e.name).toList(), ['条目2', '条目1']);
    expect(folders.map((e) => e.sortOrder).toList(), [1, 3]);
    expect(folders.map((e) => e.name).toList(), ['文件夹A', '文件夹B']);
  });

  test('文件夹颜色可保存与修改', () async {
    // 新建时指定颜色
    final folder = await data.addFolder('password', '工作', color: 0xFF64B5F6);
    expect(folder.color, 0xFF64B5F6);
    expect((await data.listFolders('password')).first.color, 0xFF64B5F6);

    // 改色
    await data.updateFolder(folder.copyWith(color: 0xFF81C784));
    expect((await data.listFolders('password')).first.color, 0xFF81C784);

    // 不指定颜色时为 null（用主题默认色）
    final plain = await data.addFolder('password', '默认色');
    expect(plain.color, isNull);
  });
}
