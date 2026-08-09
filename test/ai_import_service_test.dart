/// AI 识别结果解析与批量导入端到端测试。
library;

import 'dart:convert';

import 'package:easypassword/core/constants.dart';
import 'package:easypassword/services/ai_import_service.dart';
import 'package:easypassword/services/crypto_service.dart';
import 'package:easypassword/services/data_service.dart';
import 'package:easypassword/services/database.dart';
import 'package:easypassword/services/plain_transfer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('JSON 提取', () {
    test('识别 ```json 代码块', () {
      final text = AiImportService.extractJsonText('''
好的，识别结果如下：
```json
{"items": [{"name": "A"}]}
```
希望有帮助。''');
      expect(jsonDecode(text), isA<Map>());
      expect(text.trim().startsWith('{'), isTrue);
    });

    test('识别不带语言标记的代码块', () {
      final text = AiImportService.extractJsonText('```\n{"items": []}\n```');
      expect(jsonDecode(text)['items'], isEmpty);
    });

    test('裸 JSON 前后夹带解释文字仍能提取', () {
      final text = AiImportService.extractJsonText(
          '这是结果：{"items": [{"name": "A"}]} 请查收');
      expect(jsonDecode(text)['items'], hasLength(1));
    });

    test('结尾解释文字里的花括号不会破坏提取', () {
      // lastIndexOf('}') 会截到句尾的花括号，深度计数才能正确断句
      final text = AiImportService.extractJsonText(
          '{"items": [{"name": "A"}]}\n注意：模板 {placeholder} 需要替换');
      expect(jsonDecode(text)['items'], hasLength(1));
    });

    test('字符串内的花括号不参与深度计数', () {
      final text = AiImportService.extractJsonText(
          '{"items": [{"name": "A{B}C", "note": "含 } 符号"}]}');
      final items = jsonDecode(text)['items'] as List;
      expect((items.single as Map)['name'], 'A{B}C');
    });

    test('完全没有 JSON 时给出明确提示', () {
      expect(
        () => AiImportService.extractJsonText('抱歉，我无法识别这张图片。'),
        throwsA(isA<AiImportException>().having(
            (e) => e.message, 'message', contains('没有找到 JSON'))),
      );
    });

    test('空回复给出明确提示', () {
      expect(
        () => AiImportService.extractJsonText('   '),
        throwsA(isA<AiImportException>()),
      );
    });

    test('JSON 被截断时提示可能不完整', () {
      expect(
        () => AiImportService.extractJsonText('{"items": [{"name": "A"'),
        throwsA(isA<AiImportException>()
            .having((e) => e.message, 'message', contains('不完整'))),
      );
    });
  });

  group('结构校验', () {
    test('缺少 items 列表时报错', () {
      expect(
        () => AiImportService.parseAiJson('{"data": []}'),
        throwsA(isA<AiImportException>()
            .having((e) => e.message, 'message', contains('缺少 items'))),
      );
    });

    test('items 为空数组时提示没有识别到凭据', () {
      expect(
        () => AiImportService.parseAiJson('{"items": []}'),
        throwsA(isA<AiImportException>()
            .having((e) => e.message, 'message', contains('没有识别到'))),
      );
    });

    test('条目缺少名称时按第 N 项定位', () {
      expect(
        () => AiImportService.parseAiJson(
            '{"items": [{"type": "password", "name": "A"}, '
            '{"type": "password", "name": ""}]}'),
        throwsA(isA<AiImportException>()
            .having((e) => e.message, 'message', contains('第 2 项'))),
      );
    });

    test('type 非法时提示合法取值', () {
      expect(
        () => AiImportService.parseAiJson(
            '{"items": [{"type": "note", "name": "A"}]}'),
        throwsA(isA<AiImportException>().having((e) => e.message, 'message',
            allOf(contains('第 1 项'), contains(ItemType.password)))),
      );
    });

    test('accounts 不是列表时报错', () {
      expect(
        () => AiImportService.parseAiJson(
            '{"items": [{"type": "password", "name": "A", "accounts": "x"}]}'),
        throwsA(isA<AiImportException>()
            .having((e) => e.message, 'message', contains('accounts'))),
      );
    });

    test('顶层不是对象时报错', () {
      expect(
        () => AiImportService.parseAiJson('[1, 2]'),
        throwsA(isA<AiImportException>()),
      );
    });
  });

  group('批量统计与警告', () {
    test('跨条目累计账号数与密钥数', () {
      final result = AiImportService.parseAiJson(jsonEncode({
        'items': [
          {
            'type': ItemType.password,
            'name': 'GitHub',
            'accounts': [
              {'username': 'a', 'password': 'p1'},
              {'username': 'b', 'password': 'p2'},
            ],
          },
          {
            'type': ItemType.apikey,
            'name': 'OpenAI',
            'accounts': [
              {
                'username': 'c',
                'password': '',
                'api_keys': [
                  {'key': 'sk-1'},
                  {'key': 'sk-2'},
                  {'key': 'sk-3'},
                ],
              },
            ],
          },
        ],
      }));
      expect(result.itemCount, 2);
      expect(result.accountCount, 3);
      expect(result.apiKeyCount, 3);
      expect(result.summary, contains('2 个条目'));
      expect(result.summary, contains('3 个账号'));
      expect(result.summary, contains('3 个 API Key'));
    });

    test('AI 自报的 warnings 会透传', () {
      final result = AiImportService.parseAiJson(jsonEncode({
        'items': [
          {
            'type': ItemType.password,
            'name': 'A',
            'accounts': [
              {'username': 'u', 'password': 'p'}
            ],
          }
        ],
        'warnings': ['第 1 项：密码可能被遮挡'],
      }));
      expect(result.warnings, contains('第 1 项：密码可能被遮挡'));
    });

    test('warnings 是单个字符串时也能收集', () {
      final result = AiImportService.parseAiJson(jsonEncode({
        'items': [
          {
            'type': ItemType.password,
            'name': 'A',
            'accounts': [
              {'username': 'u', 'password': 'p'}
            ],
          }
        ],
        'warnings': '只有一条提示',
      }));
      expect(result.warnings, contains('只有一条提示'));
    });

    test('条目没有账号时本地补充警告', () {
      final result = AiImportService.parseAiJson(
          '{"items": [{"type": "password", "name": "空壳"}]}');
      expect(result.warnings.single, contains('没有识别到账号'));
    });

    test('账号既无用户名也无密码时本地补充警告', () {
      final result = AiImportService.parseAiJson(jsonEncode({
        'items': [
          {
            'type': ItemType.password,
            'name': 'A',
            'accounts': [
              {'username': '', 'password': '', 'note': '只有备注'}
            ],
          }
        ],
      }));
      expect(result.warnings.single, contains('既无用户名也无密码'));
    });

    test('API Key 允许写成裸字符串，空值被跳过', () {
      final result = AiImportService.parseAiJson(jsonEncode({
        'items': [
          {
            'type': ItemType.apikey,
            'name': 'A',
            'accounts': [
              {
                'username': 'u',
                'api_keys': ['sk-plain', '', {'key': 'sk-obj', 'note': 'n'}],
              }
            ],
          }
        ],
      }));
      expect(result.apiKeyCount, 2);
    });
  });

  group('批量导入端到端', () {
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

    test('一次导入多个条目、多个账号与多个密钥', () async {
      final result = AiImportService.parseAiJson(jsonEncode({
        'items': [
          {
            'type': ItemType.password,
            'name': 'GitHub',
            'url': 'https://github.com',
            'folder': '工作',
            'accounts': [
              {'username': 'alice', 'password': 'pw1', 'note': '主账号'},
              {'username': 'alice-bot', 'password': 'pw2', 'note': '机器人'},
            ],
          },
          {
            'type': ItemType.password,
            'name': '知乎',
            'accounts': [
              {'username': '13800138000', 'password': 'pw3'},
            ],
          },
          {
            'type': ItemType.apikey,
            'name': 'OpenAI',
            'accounts': [
              {
                'username': 'alice@example.com',
                'password': '',
                'api_keys': [
                  {'key': 'sk-prod', 'note': '生产'},
                  {'key': 'sk-test', 'note': '测试'},
                ],
              },
            ],
          },
        ],
      }));

      // 解析结果直接喂给现有明文导入管道
      final imported = await plainTransfer.importPlainText(
        result.toImportJson(),
        mode: PlainImportMode.merge,
      );
      expect(imported.addedItems, 3);

      final db = await DatabaseService.db;
      final items = await db.query('password_items', where: 'deleted = 0');
      expect(items, hasLength(3));

      final accounts = await db.query('accounts', where: 'deleted = 0');
      expect(accounts, hasLength(4));

      final keys = await db.query('api_keys', where: 'deleted = 0');
      expect(keys, hasLength(2));

      // 文件夹按名称自动创建
      final folders = await db.query('folders', where: 'deleted = 0');
      expect(folders.single['name'], '工作');

      // 密码落库为密文，读出来能还原
      final githubItem = items.firstWhere((row) => row['name'] == 'GitHub');
      final githubAccounts = await db.query('accounts',
          where: 'item_id = ? AND deleted = 0',
          whereArgs: [githubItem['id']],
          orderBy: 'sort_order ASC');
      expect(githubAccounts, hasLength(2));
      final firstEnc = githubAccounts.first['password_enc'] as String;
      expect(firstEnc, isNot('pw1'));
      expect(await crypto.decrypt(firstEnc), 'pw1');

      // API Key 同样加密落库
      final keyEnc = keys.first['key_enc'] as String;
      expect(keyEnc, isNot(contains('sk-')));
      final decryptedKeys = <String>[
        for (final row in keys)
          await crypto.decrypt(row['key_enc'] as String),
      ];
      expect(decryptedKeys, containsAll(['sk-prod', 'sk-test']));
    });

    test('重复导入同一批结果不会产生重复条目', () async {
      final json = jsonEncode({
        'items': [
          {
            'type': ItemType.password,
            'name': 'GitHub',
            'accounts': [
              {'username': 'alice', 'password': 'pw1'},
            ],
          }
        ],
      });
      final result = AiImportService.parseAiJson(json);
      await plainTransfer.importPlainText(result.toImportJson(),
          mode: PlainImportMode.merge);
      await plainTransfer.importPlainText(result.toImportJson(),
          mode: PlainImportMode.merge);

      final db = await DatabaseService.db;
      expect(await db.query('password_items', where: 'deleted = 0'),
          hasLength(1));
      expect(await db.query('accounts', where: 'deleted = 0'), hasLength(1));
    });

    test('增量导入保留本机已有的其他条目', () async {
      final existing = await data.addItem(ItemType.password, '已有条目');
      await data.addAccount(existing.id, 'old', 'oldpw');

      final result = AiImportService.parseAiJson(jsonEncode({
        'items': [
          {
            'type': ItemType.password,
            'name': '新条目',
            'accounts': [
              {'username': 'new', 'password': 'newpw'}
            ],
          }
        ],
      }));
      await plainTransfer.importPlainText(result.toImportJson(),
          mode: PlainImportMode.merge);

      final db = await DatabaseService.db;
      final names = [
        for (final row in await db.query('password_items', where: 'deleted = 0'))
          row['name'] as String,
      ];
      expect(names, containsAll(['已有条目', '新条目']));
    });
  });
}
