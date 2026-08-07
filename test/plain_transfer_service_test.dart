/// 明文导入导出服务单元测试
library;

import 'dart:convert';

import 'package:easypassword/core/constants.dart';
import 'package:easypassword/services/crypto_service.dart';
import 'package:easypassword/services/data_service.dart';
import 'package:easypassword/services/database.dart';
import 'package:easypassword/services/plain_transfer_service.dart';
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
  late PlainTransferService plainTransfer;

  setUp(() async {
    crypto = CryptoService();
    crypto.setKey(crypto.generateDeviceKey());
    data = DataService(crypto);
    plainTransfer = PlainTransferService(crypto, data);
    final db = await DatabaseService.db;
    await db.delete('api_keys');
    await db.delete('accounts');
    await db.delete('password_items');
    await db.delete('folders');
  });

  tearDown(() async {
    await DatabaseService.resetForTest();
  });

  test('导出为可读 JSON，密码与 API Key 均为明文', () async {
    final item = await data.addItem(ItemType.password, 'GitHub',
        url: 'https://github.com', siteNote: '代码托管');
    await data.addAccount(item.id, 'alice@example.com', 'TopSecret123',
        note: '主账号');

    final exported = await plainTransfer.exportPlainText();
    expect(exported, contains('"format": "EasyPassword-plain"'));
    expect(exported, contains('TopSecret123'));
    expect(exported, contains('alice@example.com'));
    expect(exported, contains('代码托管'));
    expect(exported, contains('明文备份'));
  });

  test('导出的 JSON 结构层次化，导入另一端可完整还原', () async {
    final item = await data.addItem(ItemType.apikey, 'OpenAI');
    final acc = await data.addAccount(item.id, 'team@openai.com', 'pwd');
    await data.addApiKey(acc.id, 'sk-proj-abc', note: '生产');
    await data.addApiKey(acc.id, 'sk-proj-xyz', note: '测试');

    final exported = await plainTransfer.exportPlainText();
    final decoded = jsonDecode(exported) as Map<String, dynamic>;
    final items = decoded['items'] as List;
    expect(items.length, 1);
    final first = items.single as Map<String, dynamic>;
    expect(first['name'], 'OpenAI');
    final accounts = first['accounts'] as List;
    expect(accounts.length, 1);
    final keys = (accounts.single as Map<String, dynamic>)['api_keys'] as List;
    expect(keys.length, 2);
    expect((keys.first as Map<String, dynamic>)['key'], 'sk-proj-abc');
    expect((keys.first as Map<String, dynamic>)['note'], '生产');

    // 清空后再导入同一份文件，数据应完整还原
    final db = await DatabaseService.db;
    await db.delete('api_keys');
    await db.delete('accounts');
    await db.delete('password_items');
    await plainTransfer.importPlainText(exported,
        mode: PlainImportMode.merge);

    final restoredItems =
        await data.listItems(ItemType.apikey, allFolders: true);
    final restoredAccounts = await data.listAccounts(restoredItems.single.id);
    final restoredKeys = await data.listApiKeys(restoredAccounts.single.id);
    expect(await data.plainPassword(restoredAccounts.single), 'pwd');
    expect(restoredKeys.length, 2);
    expect(await data.plainKey(restoredKeys.first), 'sk-proj-abc');
    expect(restoredKeys.first.note, '生产');
  });

  test('增量导入只新增与更新，保留本地其他数据', () async {
    await data.addItem(ItemType.password, '本地条目');
    const text = '''
    {
      "format": "EasyPassword-plain",
      "items": [
        {
          "type": "password",
          "name": "新增条目",
          "url": "",
          "note": "",
          "folder": "",
          "accounts": [{"username": "user", "password": "pass", "note": "", "api_keys": []}]
        }
      ]
    }
    ''';

    final result = await plainTransfer.importPlainText(text,
        mode: PlainImportMode.merge);
    expect(result.addedItems, 1);
    expect(result.removedItems, 0);

    final items = await data.listItems(ItemType.password, allFolders: true);
    expect(items.length, 2);
    expect(items.any((i) => i.name == '本地条目'), isTrue);
    expect(items.any((i) => i.name == '新增条目'), isTrue);
  });

  test('覆盖导入删除文件中不存在的数据，写墓碑而非物理删除', () async {
    final local = await data.addItem(ItemType.password, '待删除条目');
    await data.addAccount(local.id, 'local-user', 'local-pass');

    const text = '''
    {
      "format": "EasyPassword-plain",
      "items": [
        {
          "type": "password",
          "name": "唯一保留",
          "url": "",
          "note": "",
          "folder": "",
          "accounts": [{"username": "only", "password": "one", "note": "", "api_keys": []}]
        }
      ]
    }
    ''';

    final result = await plainTransfer.importPlainText(text,
        mode: PlainImportMode.replace);
    expect(result.addedItems, 1);
    expect(result.removedItems, 1);

    final visible = await data.listItems(ItemType.password, allFolders: true);
    expect(visible.length, 1);
    expect(visible.first.name, '唯一保留');

    // 被删数据留有墓碑，后续同步不会复活
    final db = await DatabaseService.db;
    final tombstone = await db.query(
      'password_items',
      where: 'id = ?',
      whereArgs: [local.id],
    );
    expect(tombstone.single['deleted'], 1);
    expect(tombstone.single['updated_at'], isPositive);
  });

  test('覆盖导入的删除墓碑带有导入时刻的 updated_at', () async {
    final old = await data.addItem(ItemType.password, '旧条目');
    await Future.delayed(const Duration(milliseconds: 10));

    await plainTransfer.importPlainText(
      '{"format": "EasyPassword-plain", "items": []}',
      mode: PlainImportMode.replace,
    );

    final db = await DatabaseService.db;
    final row = await db.query(
      'password_items',
      where: 'id = ?',
      whereArgs: [old.id],
    );
    final updatedAt = row.single['updated_at'] as int;
    final createdAt = row.single['created_at'] as int;
    // 墓碑的 updated_at 必须晚于创建时间，才能在同步时胜过远端旧行
    expect(updatedAt, greaterThan(createdAt));
  });

  test('导入后新增行的 updated_at 使用导入时刻', () async {
    final beforeImport = DateTime.now().millisecondsSinceEpoch;
    await Future.delayed(const Duration(milliseconds: 5));

    await plainTransfer.importPlainText(
      '''
      {
        "format": "EasyPassword-plain",
        "items": [{
          "type": "password",
          "name": "新增",
          "url": "",
          "note": "",
          "folder": "",
          "accounts": [{"username": "u", "password": "p", "note": "", "api_keys": []}]
        }]
      }
      ''',
      mode: PlainImportMode.merge,
    );

    final afterImport = DateTime.now().millisecondsSinceEpoch;
    final items = await data.listItems(ItemType.password, allFolders: true);
    final imported = items.single;
    expect(imported.updatedAt.millisecondsSinceEpoch,
        greaterThanOrEqualTo(beforeImport));
    expect(
        imported.updatedAt.millisecondsSinceEpoch, lessThanOrEqualTo(afterImport));
  });

  test('同一条目按名称匹配，内容变化时才更新', () async {
    final item =
        await data.addItem(ItemType.password, '不变', url: 'https://a.com');
    final originalTime = item.updatedAt.millisecondsSinceEpoch;
    await Future.delayed(const Duration(milliseconds: 10));

    await plainTransfer.importPlainText(
      '''
      {
        "format": "EasyPassword-plain",
        "items": [{
          "type": "password",
          "name": "不变",
          "url": "https://a.com",
          "note": "",
          "folder": "",
          "accounts": []
        }]
      }
      ''',
      mode: PlainImportMode.merge,
    );

    final unchanged = (await data.listItems(ItemType.password, allFolders: true)).single;
    // 内容完全相同时不写库，避免无意义地刷新 updated_at
    expect(unchanged.updatedAt.millisecondsSinceEpoch, originalTime);
  });

  test('文件夹按名称匹配，同名文件夹不重复创建', () async {
    await data.addFolder(ItemType.password, '工作');
    await plainTransfer.importPlainText(
      '''
      {
        "format": "EasyPassword-plain",
        "items": [
          {
            "type": "password",
            "name": "条目1",
            "folder": "工作",
            "url": "", "note": "",
            "accounts": []
          },
          {
            "type": "password",
            "name": "条目2",
            "folder": "工作",
            "url": "", "note": "",
            "accounts": []
          }
        ]
      }
      ''',
      mode: PlainImportMode.merge,
    );

    final folders = await data.listFolders(ItemType.password);
    expect(folders.length, 1);
    expect(folders.single.name, '工作');

    final items = await data.listItems(ItemType.password, allFolders: true);
    expect(items.length, 2);
    expect(items.every((i) => i.folderId == folders.single.id), isTrue);
  });

  test('增量导入时改文件夹会新增一条，原条目保留', () async {
    // 明文文件不含 id，条目身份由 (类型, 文件夹名, 条目名) 决定。
    // 因此改动文件夹等同于换了一个身份：增量模式下会新增而非移动。
    await data.addItem(ItemType.password, '同名条目');

    await plainTransfer.importPlainText(
      '''
      {
        "format": "EasyPassword-plain",
        "items": [{
          "type": "password",
          "name": "同名条目",
          "folder": "工作",
          "url": "", "note": "",
          "accounts": []
        }]
      }
      ''',
      mode: PlainImportMode.merge,
    );

    final items = await data.listItems(ItemType.password, allFolders: true);
    expect(items.length, 2);
    // 根目录的原条目仍在，文件夹内新增了一条
    expect(items.where((item) => item.folderId == null).length, 1);
    expect(items.where((item) => item.folderId != null).length, 1);
  });

  test('覆盖导入时改文件夹表现为移动，不会留下重复条目', () async {
    final origin = await data.addItem(ItemType.password, '同名条目');

    await plainTransfer.importPlainText(
      '''
      {
        "format": "EasyPassword-plain",
        "items": [{
          "type": "password",
          "name": "同名条目",
          "folder": "工作",
          "url": "", "note": "",
          "accounts": []
        }]
      }
      ''',
      mode: PlainImportMode.replace,
    );

    // 覆盖模式为原条目写墓碑，可见列表里只剩文件夹内那一条
    final visible = await data.listItems(ItemType.password, allFolders: true);
    expect(visible.length, 1);
    expect(visible.single.folderId, isNotNull);

    final db = await DatabaseService.db;
    final tombstone = await db
        .query('password_items', where: 'id = ?', whereArgs: [origin.id]);
    expect(tombstone.single['deleted'], 1);
  });

  test('格式非法时抛出可操作的异常', () async {
    expect(
      () => plainTransfer.importPlainText('not json',
          mode: PlainImportMode.merge),
      throwsA(isA<PlainImportException>()
          .having((e) => e.message, 'message', contains('不是有效的 JSON'))),
    );

    expect(
      () => plainTransfer.importPlainText('{"items": "not a list"}',
          mode: PlainImportMode.merge),
      throwsA(isA<PlainImportException>()
          .having((e) => e.message, 'message', contains('缺少 items 列表'))),
    );

    expect(
      () => plainTransfer.importPlainText(
          '{"items": [{"type": "password", "accounts": []}]}',
          mode: PlainImportMode.merge),
      throwsA(isA<PlainImportException>()
          .having((e) => e.message, 'message', contains('缺少名称'))),
    );
  });

  test('导入容忍手工编辑的非字符串值', () async {
    // 数值、布尔会转字符串，方便编辑时省略引号
    await plainTransfer.importPlainText(
      '''
      {
        "format": "EasyPassword-plain",
        "items": [{
          "type": "password",
          "name": 123,
          "url": true,
          "note": "",
          "folder": "",
          "accounts": []
        }]
      }
      ''',
      mode: PlainImportMode.merge,
    );

    final items = await data.listItems(ItemType.password, allFolders: true);
    expect(items.single.name, '123');
    expect(items.single.url, 'true');
  });

  test('导入密文字段会用本机密钥重新加密', () async {
    await plainTransfer.importPlainText(
      '''
      {
        "format": "EasyPassword-plain",
        "items": [{
          "type": "password",
          "name": "重加密测试",
          "url": "", "note": "", "folder": "",
          "accounts": [{"username": "u", "password": "明文密码", "note": "", "api_keys": []}]
        }]
      }
      ''',
      mode: PlainImportMode.merge,
    );

    final items = await data.listItems(ItemType.password, allFolders: true);
    final accounts = await data.listAccounts(items.single.id);
    final decrypted = await data.plainPassword(accounts.single);
    expect(decrypted, '明文密码');

    // 验证确实加密了，不是直接存明文
    final db = await DatabaseService.db;
    final row = await db.query('accounts', where: 'id = ?', whereArgs: [accounts.single.id]);
    expect(row.single['password_enc'], isNot('明文密码'));
  });

  test('覆盖导入的删除不会被远端旧快照复活', () async {
    // 设备 A 的既有数据先生成一份远端快照，模拟其他设备已经上传过的状态。
    final webdav = WebDavService(crypto, data);
    final stale = await data.addItem(ItemType.password, '远端仍存在的条目');
    await data.addAccount(stale.id, 'old-user', 'old-pass');
    final remoteSnapshot = await webdav.buildSnapshot();

    // 本机执行覆盖导入，把这条数据删掉。
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await plainTransfer.importPlainText(
      '''
      {
        "format": "EasyPassword-plain",
        "items": [{
          "type": "password",
          "name": "导入保留的条目",
          "url": "", "note": "", "folder": "",
          "accounts": [{"username": "u", "password": "p", "note": "", "api_keys": []}]
        }]
      }
      ''',
      mode: PlainImportMode.replace,
    );

    // 与远端旧快照合并：墓碑的 updated_at 更新，删除必须继续生效。
    await webdav.mergeSnapshot(remoteSnapshot);
    final names =
        (await data.listItems(ItemType.password, allFolders: true))
            .map((item) => item.name)
            .toList();
    expect(names, ['导入保留的条目']);

    // 账号层同样不能复活，否则详情页会出现无主的旧密码。
    expect(await data.listAccounts(stale.id), isEmpty);
  });

  test('导入结果会进入同步日志，等待推送到其他设备', () async {
    final db = await DatabaseService.db;
    await db.delete('sync_journal');

    await plainTransfer.importPlainText(
      '''
      {
        "format": "EasyPassword-plain",
        "items": [{
          "type": "password",
          "name": "待推送",
          "url": "", "note": "", "folder": "",
          "accounts": [{"username": "u", "password": "p", "note": "", "api_keys": []}]
        }]
      }
      ''',
      mode: PlainImportMode.merge,
    );

    expect(await DatabaseService.hasPendingSyncChanges(), isTrue);
  });

  test('导入统计返回实际生效的条数', () async {
    await data.addItem(ItemType.password, '已有');

    final result = await plainTransfer.importPlainText(
      '''
      {
        "format": "EasyPassword-plain",
        "items": [
          {
            "type": "password",
            "name": "已有",
            "url": "新URL",
            "note": "", "folder": "",
            "accounts": []
          },
          {
            "type": "password",
            "name": "新增",
            "url": "", "note": "", "folder": "",
            "accounts": [{"username": "u", "password": "p", "note": "", "api_keys": []}]
          }
        ]
      }
      ''',
      mode: PlainImportMode.merge,
    );

    expect(result.addedItems, 1);
    expect(result.updatedItems, 1);
    expect(result.accounts, 1);
    expect(result.summary, contains('新增 1 项'));
    expect(result.summary, contains('更新 1 项'));
  });
}
