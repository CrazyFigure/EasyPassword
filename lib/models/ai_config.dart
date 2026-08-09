/// AI 识别接入点配置模型：协议格式、模型清单与整体配置集合。
///
/// 设计要点：
/// 1. 全部 fromJson 都做缺失与类型容错，任何字段异常都回退默认值而不抛异常。
///    配置会随 WebDAV 快照跨设备同步，也允许用户手工编辑导出的明文备份，
///    解析失败若直接抛错会让整个设置页打不开。
/// 2. apiKey 明文保存。设置项在同步合并时按 value 原样复制
///    （见 WebDavService._applySnapshot），若用本机 device_key 加密，
///    其他设备拿到密文将无法解密。快照整体仍由 WebDAV 凭据派生密钥加密。
library;

/// AI 接入点使用的协议格式。三种格式的请求体与响应结构互不相同，
/// 由 AiHttpClient 中对应的实现类负责适配。
enum AiProviderProtocol {
  anthropic('anthropic', 'Anthropic Messages', 'https://api.anthropic.com'),
  openaiResponses(
      'openai_responses', 'OpenAI Responses', 'https://api.openai.com'),
  openaiChat(
      'openai_chat', 'OpenAI Chat Completions', 'https://api.openai.com');

  const AiProviderProtocol(this.id, this.label, this.defaultBaseUrl);

  /// 持久化值。用显式字符串而非 enum.name，避免重命名枚举时破坏历史配置。
  final String id;

  /// 界面展示名
  final String label;

  /// 新建接入点时预填的服务地址
  final String defaultBaseUrl;

  /// 未知值统一回退 anthropic：同步来的新版本配置或手工编辑出错时，
  /// 仍能打开设置页并让用户自行修正，而不是整个配置读不出来。
  static AiProviderProtocol fromId(Object? value) {
    final id = value?.toString();
    for (final protocol in AiProviderProtocol.values) {
      if (protocol.id == id) return protocol;
    }
    return AiProviderProtocol.anthropic;
  }
}

/// 接入点下的单个模型。
class AiModel {
  /// 请求体中的 model 字段，必须与服务方定义一致
  final String id;

  /// 界面展示名；为空时回退显示 id
  final String displayName;

  /// 上下文窗口 token 数，仅用于界面提示，不参与请求
  final int contextWindow;

  /// 是否具备视觉能力，决定识别页图片区是否可用
  final bool supportsVision;

  const AiModel({
    required this.id,
    this.displayName = '',
    this.contextWindow = 0,
    this.supportsVision = false,
  });

  /// 列表与下拉里显示的名称
  String get label => displayName.trim().isEmpty ? id : displayName.trim();

  AiModel copyWith({
    String? id,
    String? displayName,
    int? contextWindow,
    bool? supportsVision,
  }) {
    return AiModel(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      contextWindow: contextWindow ?? this.contextWindow,
      supportsVision: supportsVision ?? this.supportsVision,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'display_name': displayName,
        'context_window': contextWindow,
        'supports_vision': supportsVision,
      };

  factory AiModel.fromJson(Map<String, dynamic> json) {
    return AiModel(
      id: _asString(json['id']),
      displayName: _asString(json['display_name']),
      contextWindow: _asInt(json['context_window']),
      supportsVision: _asBool(json['supports_vision']),
    );
  }
}

/// 一个 AI 接入点：一组服务地址 + 凭据 + 可用模型。
class AiProvider {
  /// 本地唯一 id，由 DataService.genId() 生成
  final String id;
  final String name;
  final AiProviderProtocol protocol;
  final String baseUrl;

  /// 明文保存，原因见文件头注释
  final String apiKey;
  final List<AiModel> models;

  /// 附加请求头，每项形如 "Header-Name: value"，用于兼容中转网关
  final List<String> extraHeaders;

  const AiProvider({
    required this.id,
    required this.name,
    required this.protocol,
    required this.baseUrl,
    required this.apiKey,
    this.models = const [],
    this.extraHeaders = const [],
  });

  /// 列表里显示的名称；未命名时回退协议名，避免出现空白行
  String get label => name.trim().isEmpty ? protocol.label : name.trim();

  AiProvider copyWith({
    String? id,
    String? name,
    AiProviderProtocol? protocol,
    String? baseUrl,
    String? apiKey,
    List<AiModel>? models,
    List<String>? extraHeaders,
  }) {
    return AiProvider(
      id: id ?? this.id,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
      extraHeaders: extraHeaders ?? this.extraHeaders,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'protocol': protocol.id,
        'base_url': baseUrl,
        'api_key': apiKey,
        'models': [for (final model in models) model.toJson()],
        'extra_headers': extraHeaders,
      };

  factory AiProvider.fromJson(Map<String, dynamic> json) {
    return AiProvider(
      id: _asString(json['id']),
      name: _asString(json['name']),
      protocol: AiProviderProtocol.fromId(json['protocol']),
      baseUrl: _asString(json['base_url']),
      apiKey: _asString(json['api_key']),
      models: [
        for (final raw in _asList(json['models']))
          if (raw is Map) AiModel.fromJson(Map<String, dynamic>.from(raw)),
      ],
      extraHeaders: [
        for (final raw in _asList(json['extra_headers']))
          if (_asString(raw).trim().isNotEmpty) _asString(raw).trim(),
      ],
    );
  }

  /// 解析附加请求头为可直接合并进请求的 map。
  /// 非法行（没有冒号或键为空）静默跳过，不阻断请求。
  Map<String, String> parseExtraHeaders() {
    final headers = <String, String>{};
    for (final line in extraHeaders) {
      final index = line.indexOf(':');
      if (index <= 0) continue;
      final key = line.substring(0, index).trim();
      final value = line.substring(index + 1).trim();
      if (key.isEmpty) continue;
      headers[key] = value;
    }
    return headers;
  }
}

/// 全部接入点的集合，整体序列化为 settings 表的单个键。
class AiProviderConfig {
  final List<AiProvider> providers;

  const AiProviderConfig({this.providers = const []});

  /// 配置结构版本。当前仅写入，供未来结构调整时判断迁移路径。
  static const int currentVersion = 1;

  Map<String, dynamic> toJson() => {
        'version': currentVersion,
        'providers': [for (final provider in providers) provider.toJson()],
      };

  factory AiProviderConfig.fromJson(Map<String, dynamic> json) {
    return AiProviderConfig(
      providers: [
        for (final raw in _asList(json['providers']))
          if (raw is Map) AiProvider.fromJson(Map<String, dynamic>.from(raw)),
      ],
    );
  }
}

// ---------- 解析辅助：一律容错，不抛异常 ----------

String _asString(Object? value) => value == null ? '' : value.toString();

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_asString(value)) ?? 0;
}

bool _asBool(Object? value) {
  if (value is bool) return value;
  final text = _asString(value).toLowerCase();
  return text == 'true' || text == '1';
}

List<Object?> _asList(Object? value) =>
    value is List ? value : const <Object?>[];
