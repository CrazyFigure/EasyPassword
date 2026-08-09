/// 识别提示词生成：schema 描述由字段规格表推导，而非硬编码整段文本。
///
/// 这样设计的原因是让提示词跟着数据模型走：以后 PasswordItem / Account /
/// ApiKey 增删字段，只需改本文件的三张规格表，提示词里的 schema 说明、
/// 必填标记、字段含义会自动跟着变，不必再逐句手改一大段中文描述。
///
/// 另外提供「自定义提示词」拼接位，让用户表达个性化要求
/// （例如「跳过免费网站」「只提取 API Key」），无需改代码。
library;

import '../core/constants.dart';

/// 一个可识别字段的规格。加字段 = 在下面的表里加一行。
class AiFieldSpec {
  /// JSON 里的键名
  final String key;

  /// 给 AI 看的中文含义
  final String label;

  /// 是否必填。必填字段缺失会在解析阶段报错
  final bool required;

  /// 附加约束说明，例如枚举取值范围
  final String note;

  const AiFieldSpec({
    required this.key,
    required this.label,
    this.required = false,
    this.note = '',
  });

  /// 渲染成 schema 里的一行注释文本
  String describe() {
    final parts = <String>[label];
    parts.add(required ? '必填' : '选填');
    if (note.isNotEmpty) parts.add(note);
    return parts.join('，');
  }
}

class AiPromptService {
  /// 第一层：条目（一个网站或应用）
  static const List<AiFieldSpec> itemFields = [
    AiFieldSpec(
      key: 'type',
      label: '条目类型',
      required: true,
      note: '只能是 ${ItemType.password} 或 ${ItemType.apikey}；'
          '识别到账号密码填 ${ItemType.password}，识别到密钥串填 ${ItemType.apikey}',
    ),
    AiFieldSpec(key: 'name', label: '网站或应用名称', required: true),
    AiFieldSpec(key: 'url', label: '网址'),
    AiFieldSpec(key: 'note', label: '网站级备注'),
    AiFieldSpec(key: 'folder', label: '所属文件夹名', note: '不存在时会自动创建'),
  ];

  /// 第二层：账号（挂在条目下）
  static const List<AiFieldSpec> accountFields = [
    AiFieldSpec(key: 'username', label: '用户名或登录邮箱'),
    AiFieldSpec(key: 'password', label: '密码'),
    AiFieldSpec(key: 'note', label: '账号级备注'),
  ];

  /// 第三层：API Key（挂在账号下）
  static const List<AiFieldSpec> apiKeyFields = [
    AiFieldSpec(key: 'key', label: '密钥原文', required: true),
    AiFieldSpec(key: 'note', label: '密钥备注', note: '例如用途或环境'),
  ];

  /// 生成结构说明。三层嵌套关系与逐层字段都由上面的规格表推导。
  static String buildSchemaDescription() {
    final buffer = StringBuffer();
    buffer.writeln('输出一个 JSON 对象，顶层只有 items 数组。');
    buffer.writeln('items 的每个元素是一个条目，结构如下：');
    buffer.writeln('{');
    for (final field in itemFields) {
      buffer.writeln('  "${field.key}": ${field.describe()}');
    }
    buffer.writeln('  "accounts": 该条目下的账号数组，每个账号：');
    buffer.writeln('  {');
    for (final field in accountFields) {
      buffer.writeln('    "${field.key}": ${field.describe()}');
    }
    buffer.writeln('    "api_keys": 该账号下的密钥数组，每个密钥：');
    buffer.writeln('    {');
    for (final field in apiKeyFields) {
      buffer.writeln('      "${field.key}": ${field.describe()}');
    }
    buffer.writeln('    }');
    buffer.writeln('  }');
    buffer.write('}');
    return buffer.toString();
  }

  /// 批量示例。实测中给出一个含多条目、多账号、多密钥的完整样例，
  /// 比只用文字描述更能让模型稳定输出多条结果，因此固定内嵌。
  static String buildBatchExample() {
    return '''
{"items":[
  {"type":"${ItemType.password}","name":"GitHub","url":"https://github.com","note":"","folder":"工作",
   "accounts":[
     {"username":"alice","password":"pw-alice","note":"主账号","api_keys":[]},
     {"username":"alice-bot","password":"pw-bot","note":"CI 机器人","api_keys":[]}
   ]},
  {"type":"${ItemType.password}","name":"知乎","url":"","note":"","folder":"",
   "accounts":[
     {"username":"13800138000","password":"pw-zhihu","note":"","api_keys":[]}
   ]},
  {"type":"${ItemType.apikey}","name":"OpenAI","url":"","note":"","folder":"AI 服务",
   "accounts":[
     {"username":"alice@example.com","password":"","note":"",
      "api_keys":[
        {"key":"sk-prod-example","note":"生产环境"},
        {"key":"sk-test-example","note":"测试环境"}
      ]}
   ]}
]}''';
  }

  /// 组装完整系统提示词。[customPrompt] 为空时不产生空白段落。
  static String buildSystemPrompt({String customPrompt = ''}) {
    final custom = customPrompt.trim();
    final buffer = StringBuffer();

    buffer.writeln('你是一个密码管理导入助手。请从用户提供的文字与图片中提取全部登录凭据，');
    buffer.writeln('并输出符合下面结构的 JSON。');
    buffer.writeln();
    buffer.writeln('【数据结构】三层嵌套：条目（网站/应用）→ 账号 → API Key');
    buffer.writeln(buildSchemaDescription());
    buffer.writeln();
    buffer.writeln('【批量要求】');
    buffer.writeln('1. items 可以包含多个条目：识别到几个网站或应用，就输出几个条目。');
    buffer.writeln('2. 同一个网站有多个账号时，放进该条目的 accounts 数组，不要拆成多个条目。');
    buffer.writeln('3. 同一个账号有多个密钥时，全部放进该账号的 api_keys 数组。');
    buffer.writeln('4. 不要因为内容多就省略、合并或只取前几条，识别到多少就输出多少。');
    buffer.writeln();
    buffer.writeln('【示例】以下示例包含 2 个密码条目和 1 个 API Key 条目，');
    buffer.writeln('其中 GitHub 有两个账号，OpenAI 的账号下有两个密钥：');
    buffer.writeln(buildBatchExample());
    buffer.writeln();
    buffer.writeln('【输出规则】');
    buffer.writeln('1. 只输出一个 JSON 对象，不要输出任何解释文字，不要用 markdown 代码块包裹。');
    buffer.writeln('2. 无法确定的选填字段填空字符串 ""，绝对不要编造内容。');
    buffer.writeln('3. 即使某条凭据连名称都无法确认，也要放进 items，name 填你能推断的最接近值。');
    buffer.writeln('4. 如果识别结果存在不确定或缺漏（例如密码被遮挡、用户名模糊），');
    buffer.writeln('   在顶层追加 "warnings" 字符串数组说明，最多 5 条，例如：');
    buffer.writeln('   "warnings":["第 1 项：密码可能不完整","第 3 项：未能识别用户名"]');

    if (custom.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('【用户附加要求】');
      buffer.writeln(custom);
    }

    return buffer.toString().trimRight();
  }

  /// 识别请求的用户消息。图片与文本都可能为空，这里给出兜底指引。
  static String buildUserText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return '请识别我上传的图片中的全部登录凭据，按要求输出 JSON。';
    }
    return trimmed;
  }
}
