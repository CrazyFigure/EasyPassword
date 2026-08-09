/// AI 识别结果的提取、校验与导入编排。
///
/// 职责分三段：
/// 1. extractJsonText —— 从可能夹带解释文字或 markdown 代码块的回复里取出 JSON；
/// 2. parseAiJson —— 校验结构并汇总批量统计与缺失信息提示；
/// 3. recognize —— 串起提示词生成、AI 调用与解析。
///
/// 校验刻意在写库之前完成，且错误文案沿用 PlainTransferService 的「第 N 项」
/// 定位风格，让用户能对着预览定位到具体哪一条有问题。真正写库仍复用
/// PlainTransferService.importPlainText，事务、加密、墓碑与同步全部现成。
library;

import 'dart:convert';

import '../core/constants.dart';
import '../models/ai_config.dart';
import 'ai_http_client.dart';
import 'ai_prompt_service.dart';

/// 识别结果无法使用时抛出，[message] 可直接展示给用户。
class AiImportException implements Exception {
  final String message;
  const AiImportException(this.message);

  @override
  String toString() => message;
}

/// 解析并校验后的识别结果，可直接喂给 PlainTransferService。
class AiParseResult {
  /// 每项形如 {type, name, url, note, folder, accounts}
  final List<Map<String, dynamic>> items;

  /// AI 自报的缺失信息 + 本地补充的判定结果
  final List<String> warnings;

  const AiParseResult({required this.items, this.warnings = const []});

  int get itemCount => items.length;

  /// 账号总数（跨全部条目累加）
  int get accountCount {
    var total = 0;
    for (final item in items) {
      total += _accountsOf(item).length;
    }
    return total;
  }

  /// API Key 总数（跨全部条目与账号累加）
  int get apiKeyCount {
    var total = 0;
    for (final item in items) {
      for (final account in _accountsOf(item)) {
        final keys = account['api_keys'];
        if (keys is List) total += keys.length;
      }
    }
    return total;
  }

  /// 界面用的一句话统计
  String get summary {
    final parts = <String>['识别到 $itemCount 个条目', '共 $accountCount 个账号'];
    if (apiKeyCount > 0) parts.add('$apiKeyCount 个 API Key');
    return parts.join('，');
  }

  /// 可导入的 JSON 文本。PlainTransferService._decode 不校验 format 与 version，
  /// 只要顶层是对象且含 items 即可直接导入。
  String toImportJson() => jsonEncode({'items': items});

  /// 供界面折叠展示的美化 JSON
  String toPrettyJson() =>
      const JsonEncoder.withIndent('  ').convert({'items': items});

  static List<Map<String, dynamic>> _accountsOf(Map<String, dynamic> item) {
    final accounts = item['accounts'];
    if (accounts is! List) return const [];
    return [
      for (final account in accounts)
        if (account is Map) Map<String, dynamic>.from(account),
    ];
  }
}

class AiImportService {
  AiImportService({AiHttpSender? sender}) : _sender = sender;

  /// 仅测试注入
  final AiHttpSender? _sender;

  /// 完整识别流程：组装提示词 → 调用 AI → 提取并校验 JSON。
  Future<AiParseResult> recognize({
    required AiProvider provider,
    required AiModel model,
    required String text,
    List<AiImageInput> images = const [],
    String customPrompt = '',
  }) async {
    final client = AiClientFactory.forProtocol(provider.protocol,
        sender: _sender);
    final response = await client.chat(
      provider,
      model,
      AiChatRequest(
        systemPrompt: AiPromptService.buildSystemPrompt(
          customPrompt: customPrompt,
        ),
        userText: AiPromptService.buildUserText(text),
        images: images,
      ),
    );
    return parseAiJson(extractJsonText(response.text));
  }

  /// 连接测试：发一条最小请求，能拿到任意文本即视为通道可用。
  Future<void> testConnection(AiProvider provider, AiModel model) async {
    final client = AiClientFactory.forProtocol(provider.protocol,
        sender: _sender);
    await client.chat(
      provider,
      model,
      const AiChatRequest(
        systemPrompt: '你是一个连通性测试助手。',
        userText: '请只回复 OK 两个字符。',
      ),
    );
  }

  /// 从 AI 回复里取出 JSON 文本。
  ///
  /// 依次尝试：markdown 代码块 → 从首个 `{` 起按大括号深度扫描到配对的 `}`。
  /// 用深度计数而不是 lastIndexOf('}')，因为回复末尾可能跟着解释文字，
  /// 其中夹带的花括号会让「取最后一个」截出一段非法 JSON。
  static String extractJsonText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      throw const AiImportException('AI 返回内容为空，请重试');
    }

    // 1) ```json ... ``` 或 ``` ... ``` 代码块
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
        .firstMatch(text);
    if (fence != null) {
      final inner = fence.group(1)?.trim() ?? '';
      if (inner.startsWith('{')) return _scanBalanced(inner);
    }

    // 2) 从首个 { 起扫描
    return _scanBalanced(text);
  }

  /// 从首个 `{` 开始按深度计数截取配对的对象文本；字符串内的花括号不计数。
  static String _scanBalanced(String text) {
    final start = text.indexOf('{');
    if (start < 0) {
      throw const AiImportException('AI 返回的内容中没有找到 JSON 数据');
    }
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var i = start; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return text.substring(start, i + 1);
      }
    }
    throw const AiImportException('AI 返回的 JSON 不完整，可能被截断，请重试');
  }

  /// 校验结构并整理成可导入的结果。任何问题都在写库之前抛出。
  static AiParseResult parseAiJson(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } catch (_) {
      throw const AiImportException('AI 返回的内容不是有效的 JSON，请重试');
    }
    if (decoded is! Map) {
      throw const AiImportException('AI 返回结构不正确：顶层应为 JSON 对象');
    }
    final snapshot = Map<String, dynamic>.from(decoded);

    final rawItems = snapshot['items'];
    if (rawItems is! List) {
      throw const AiImportException('AI 返回结构不正确：缺少 items 列表');
    }
    if (rawItems.isEmpty) {
      throw const AiImportException('AI 没有识别到任何凭据，请补充更清晰的图片或文字');
    }

    final warnings = <String>[
      // AI 自报的缺失信息优先展示
      for (final warning in _stringList(snapshot['warnings']))
        if (warning.trim().isNotEmpty) warning.trim(),
    ];

    final items = <Map<String, dynamic>>[];
    for (var i = 0; i < rawItems.length; i++) {
      final raw = rawItems[i];
      // 位置用「第 N 项」而非数组下标，与明文导入的报错风格一致
      final position = '第 ${i + 1} 项';
      if (raw is! Map) {
        throw AiImportException('$position 不是有效的条目对象');
      }
      final item = Map<String, dynamic>.from(raw);

      final name = _string(item['name']).trim();
      if (name.isEmpty) {
        throw AiImportException('$position 缺少名称，请检查识别结果后重试');
      }
      final type = _string(item['type']).trim();
      if (type != ItemType.password && type != ItemType.apikey) {
        throw AiImportException(
            '$position（$name）的 type 必须是 ${ItemType.password} 或 ${ItemType.apikey}');
      }
      final rawAccounts = item['accounts'];
      if (rawAccounts != null && rawAccounts is! List) {
        throw AiImportException('$position（$name）的 accounts 必须是列表');
      }

      final accounts = <Map<String, dynamic>>[];
      var hasCredential = false;
      for (final rawAccount in (rawAccounts as List?) ?? const []) {
        if (rawAccount is! Map) {
          throw AiImportException('$position（$name）内含无效的账号对象');
        }
        final account = Map<String, dynamic>.from(rawAccount);
        final rawKeys = account['api_keys'];
        if (rawKeys != null && rawKeys is! List) {
          throw AiImportException('$position（$name）的 api_keys 必须是列表');
        }

        final keys = <Map<String, dynamic>>[];
        for (final rawKey in (rawKeys as List?) ?? const []) {
          // 允许直接写字符串，手工编辑预览时可省掉备注字段
          if (rawKey is String) {
            if (rawKey.trim().isEmpty) continue;
            keys.add({'key': rawKey, 'note': ''});
          } else if (rawKey is Map) {
            final key = _string(rawKey['key']);
            if (key.trim().isEmpty) continue;
            keys.add({'key': key, 'note': _string(rawKey['note'])});
          } else {
            throw AiImportException('$position（$name）内含无效的 API Key');
          }
        }

        final username = _string(account['username']);
        final password = _string(account['password']);
        if (username.trim().isNotEmpty ||
            password.trim().isNotEmpty ||
            keys.isNotEmpty) {
          hasCredential = true;
        }

        accounts.add({
          'username': username,
          'password': password,
          'note': _string(account['note']),
          'api_keys': keys,
        });
      }

      // 本地补充的缺失提示：条目在但没有任何可用凭据，导入后会是空壳
      if (accounts.isEmpty) {
        warnings.add('$position（$name）没有识别到账号信息');
      } else if (!hasCredential) {
        warnings.add('$position（$name）的账号既无用户名也无密码');
      }

      items.add({
        'type': type,
        'name': name,
        'url': _string(item['url']).trim(),
        'note': _string(item['note']),
        'folder': _string(item['folder']).trim(),
        'accounts': accounts,
      });
    }

    // 提示过多会挤占界面，只保留前若干条
    const maxWarnings = 8;
    return AiParseResult(
      items: items,
      warnings: warnings.length > maxWarnings
          ? [
              ...warnings.take(maxWarnings),
              '另有 ${warnings.length - maxWarnings} 条提示未显示',
            ]
          : warnings,
    );
  }

  /// 数值、布尔等非字符串值一律转文本，容忍 AI 省略引号
  static String _string(Object? value) => value == null ? '' : value.toString();

  static List<String> _stringList(Object? value) {
    if (value is List) return [for (final item in value) _string(item)];
    // 个别模型会把 warnings 写成单个字符串
    final single = _string(value);
    return single.isEmpty ? const [] : [single];
  }
}
