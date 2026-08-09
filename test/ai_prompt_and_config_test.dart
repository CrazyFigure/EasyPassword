/// 提示词生成与配置存储测试。
library;

import 'package:easypassword/core/constants.dart';
import 'package:easypassword/models/ai_config.dart';
import 'package:easypassword/services/ai_config_service.dart';
import 'package:easypassword/services/ai_prompt_service.dart';
import 'package:easypassword/services/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  group('提示词生成', () {
    test('schema 描述覆盖三层的全部字段键', () {
      final schema = AiPromptService.buildSchemaDescription();
      for (final field in AiPromptService.itemFields) {
        expect(schema, contains('"${field.key}"'),
            reason: '条目字段 ${field.key} 应出现在 schema 中');
      }
      for (final field in AiPromptService.accountFields) {
        expect(schema, contains('"${field.key}"'));
      }
      for (final field in AiPromptService.apiKeyFields) {
        expect(schema, contains('"${field.key}"'));
      }
      // 嵌套结构必须显式出现，AI 才知道账号与密钥挂在哪一层
      expect(schema, contains('"accounts"'));
      expect(schema, contains('"api_keys"'));
    });

    test('必填与选填标记随字段规格变化', () {
      final schema = AiPromptService.buildSchemaDescription();
      // name 与 type 是必填，url 是选填
      expect(schema, contains('"name": 网站或应用名称，必填'));
      expect(schema, contains('"url": 网址，选填'));
    });

    test('type 的合法取值来自 ItemType 常量而非写死字符串', () {
      final schema = AiPromptService.buildSchemaDescription();
      expect(schema, contains(ItemType.password));
      expect(schema, contains(ItemType.apikey));
    });

    test('系统提示词包含批量要求与多条示例', () {
      final prompt = AiPromptService.buildSystemPrompt();
      expect(prompt, contains('批量要求'));
      expect(prompt, contains('识别到几个网站或应用，就输出几个条目'));
      // 示例里必须真的出现多个条目与多个账号，仅靠文字描述不足以稳定引导
      expect(prompt, contains('GitHub'));
      expect(prompt, contains('alice-bot'));
      expect(prompt, contains('sk-prod-example'));
    });

    test('输出规则要求裸 JSON 并说明 warnings 用法', () {
      final prompt = AiPromptService.buildSystemPrompt();
      expect(prompt, contains('不要用 markdown 代码块包裹'));
      expect(prompt, contains('warnings'));
    });

    test('自定义提示词为空时不产生空白段落', () {
      final prompt = AiPromptService.buildSystemPrompt(customPrompt: '   ');
      expect(prompt, isNot(contains('用户附加要求')));
    });

    test('自定义提示词追加在内置规则之后', () {
      final prompt =
          AiPromptService.buildSystemPrompt(customPrompt: '只提取 API Key');
      expect(prompt, contains('用户附加要求'));
      expect(prompt, contains('只提取 API Key'));
      expect(prompt.indexOf('只提取 API Key'),
          greaterThan(prompt.indexOf('输出规则')));
    });

    test('用户消息为空时给出兜底指引', () {
      expect(AiPromptService.buildUserText('  '), contains('图片'));
      expect(AiPromptService.buildUserText(' 识别这些 '), '识别这些');
    });
  });

  group('配置存储', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      DatabaseService.overridePath = inMemoryDatabasePath;
    });

    late AiConfigService service;

    setUp(() async {
      service = AiConfigService();
      final db = await DatabaseService.db;
      await db.delete('settings');
    });

    tearDown(() async {
      await DatabaseService.resetForTest();
    });

    AiProvider sample({String id = 'p1', String name = '接入点'}) => AiProvider(
          id: id,
          name: name,
          protocol: AiProviderProtocol.openaiChat,
          baseUrl: 'https://api.example.com',
          apiKey: 'sk-secret-value',
          models: const [
            AiModel(
                id: 'gpt-x',
                displayName: '视觉模型',
                contextWindow: 128000,
                supportsVision: true),
          ],
          extraHeaders: const ['X-Org: acme'],
        );

    test('保存后读取保持一致', () async {
      await service.saveProviders([sample()]);
      final loaded = await service.getProviders();
      expect(loaded, hasLength(1));
      final provider = loaded.single;
      expect(provider.name, '接入点');
      expect(provider.protocol, AiProviderProtocol.openaiChat);
      expect(provider.apiKey, 'sk-secret-value');
      expect(provider.models.single.contextWindow, 128000);
      expect(provider.models.single.supportsVision, isTrue);
      expect(provider.extraHeaders, ['X-Org: acme']);
    });

    test('未配置时返回空列表', () async {
      expect(await service.getProviders(), isEmpty);
    });

    test('存储内容损坏时回退空列表而不抛异常', () async {
      await DatabaseService.setSetting(DbKeys.aiProviders, '{不是合法 JSON');
      expect(await service.getProviders(), isEmpty);
    });

    test('存储内容是 JSON 数组而非对象时同样回退', () async {
      await DatabaseService.setSetting(DbKeys.aiProviders, '[1,2,3]');
      expect(await service.getProviders(), isEmpty);
    });

    test('upsert 按 id 覆盖并保持原有顺序', () async {
      await service.saveProviders([
        sample(id: 'a', name: '甲'),
        sample(id: 'b', name: '乙'),
      ]);
      await service.upsertProvider(sample(id: 'a', name: '甲改'));
      final loaded = await service.getProviders();
      expect(loaded.map((p) => p.name), ['甲改', '乙']);
    });

    test('upsert 未知 id 时追加到末尾', () async {
      await service.saveProviders([sample(id: 'a', name: '甲')]);
      await service.upsertProvider(sample(id: 'c', name: '丙'));
      final loaded = await service.getProviders();
      expect(loaded.map((p) => p.name), ['甲', '丙']);
    });

    test('删除只移除指定接入点', () async {
      await service.saveProviders([
        sample(id: 'a', name: '甲'),
        sample(id: 'b', name: '乙'),
      ]);
      await service.deleteProvider('a');
      final loaded = await service.getProviders();
      expect(loaded.single.name, '乙');
    });

    test('findProvider 找不到时返回 null', () async {
      await service.saveProviders([sample(id: 'a')]);
      expect(await service.findProvider('a'), isNotNull);
      expect(await service.findProvider('missing'), isNull);
    });

    test('自定义提示词默认空串且保存后可读回', () async {
      expect(await service.getCustomPrompt(), '');
      await service.setCustomPrompt('  只提取工作账号  ');
      expect(await service.getCustomPrompt(), '只提取工作账号');
    });

    test('保存配置会触发同步通知', () async {
      var notified = 0;
      service.onChanged = () async => notified++;
      await service.saveProviders([sample()]);
      await service.setCustomPrompt('x');
      expect(notified, 2);
    });

    test('AI 配置键在跨设备同步白名单内', () {
      // 用户选择让配置随快照同步；白名单缺失会导致改动不被推送
      expect(DatabaseService.syncableSettingKeys, contains(DbKeys.aiProviders));
      expect(
          DatabaseService.syncableSettingKeys, contains(DbKeys.aiCustomPrompt));
    });
  });
}
