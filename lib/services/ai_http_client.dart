/// AI 服务调用：统一请求模型 + 三种协议格式的适配。
///
/// 三种协议（Anthropic Messages / OpenAI Responses / OpenAI Chat Completions）
/// 的请求体与响应结构互不相同，这里用同一组输入输出模型抹平差异，
/// 上层（识别页、连接测试）只面对 AiClient.chat 一个入口。
///
/// 可测性设计对齐 UpdateService：请求体构造与响应提取都是纯函数静态方法，
/// 网络只留一层薄壳并支持注入 [AiHttpSender]，因此协议适配逻辑可以完全
/// 脱离真实网络来验证。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/ai_config.dart';

/// 随请求发送的一张图片
class AiImageInput {
  final Uint8List bytes;

  /// MIME 类型，如 image/png；由文件扩展名推导
  final String mediaType;

  /// 原始文件名，仅用于界面展示
  final String fileName;

  const AiImageInput({
    required this.bytes,
    required this.mediaType,
    this.fileName = '',
  });

  String get base64Data => base64Encode(bytes);

  /// data URL 形式，OpenAI 两种协议都用这种方式携带图片
  String get dataUrl => 'data:$mediaType;base64,$base64Data';

  /// 由文件名推导 MIME 类型；未知扩展名回退 image/png。
  /// 服务端一般按实际字节判断格式，回退值不会导致识别失败。
  static String mediaTypeOf(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.bmp')) return 'image/bmp';
    return 'image/png';
  }
}

/// 一次对话请求
class AiChatRequest {
  final String systemPrompt;
  final String userText;
  final List<AiImageInput> images;

  const AiChatRequest({
    required this.systemPrompt,
    required this.userText,
    this.images = const [],
  });
}

/// 一次对话响应
class AiChatResponse {
  /// 提取出的正文，可能含 markdown 包裹，交由上层解析
  final String text;
  final int? inputTokens;
  final int? outputTokens;

  const AiChatResponse({
    required this.text,
    this.inputTokens,
    this.outputTokens,
  });
}

/// AI 调用异常。[code] 用于上层区分处理，[message] 为可直接展示的中文提示。
///
/// code 取值：
/// network（连接失败/超时）、auth（凭据无效）、rate_limited（限流）、
/// http_status（其他响应码）、parse（响应结构无法解析）、refused（内容被拒绝）
class AiHttpException implements Exception {
  final String code;
  final String message;

  /// 服务方返回的原始错误信息，便于排查；界面按需展示
  final String detail;

  const AiHttpException(this.code, this.message, [this.detail = '']);

  @override
  String toString() => message;
}

/// 请求发送注入点：生产走真实 HTTP，测试返回构造好的响应。
typedef AiHttpSender = Future<http.Response> Function(
  Uri uri, {
  required Map<String, String> headers,
  required String body,
});

/// 各协议客户端的共同基类，统一超时、错误映射与 JSON 解码。
abstract class AiClient {
  AiClient({AiHttpSender? sender}) : _sender = sender;

  final AiHttpSender? _sender;

  /// 连接超时，对齐 UpdateService
  static const Duration connectTimeout = Duration(seconds: 15);

  /// 读取超时。识别请求含图片且要生成较长 JSON，比更新检查更慢，给到 120 秒。
  static const Duration readTimeout = Duration(seconds: 120);

  /// 单次响应的最大输出 token。识别结果是结构化 JSON，8192 足够容纳多条条目。
  static const int maxOutputTokens = 8192;

  Future<AiChatResponse> chat(
    AiProvider provider,
    AiModel model,
    AiChatRequest request,
  );

  /// 拼接服务地址与路径，容忍用户填写时结尾多写或少写斜杠。
  @visibleForTesting
  static Uri resolveEndpoint(String baseUrl, String path) {
    var base = baseUrl.trim();
    if (base.isEmpty) {
      throw const AiHttpException('http_status', '接口地址为空，请先在配置里填写');
    }
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final uri = Uri.tryParse('$base$path');
    if (uri == null || !uri.hasScheme) {
      throw AiHttpException('http_status', '接口地址无效：$baseUrl');
    }
    return uri;
  }

  /// 发送请求并完成状态码判定，返回解码后的 JSON map。
  @protected
  Future<Map<String, dynamic>> post(
    Uri uri,
    Map<String, String> headers,
    Map<String, dynamic> body,
  ) async {
    final http.Response response;
    try {
      final sender = _sender;
      if (sender != null) {
        response = await sender(uri, headers: headers, body: jsonEncode(body));
      } else {
        response = await _send(uri, headers, jsonEncode(body));
      }
    } on AiHttpException {
      rethrow;
    } on TimeoutException {
      throw const AiHttpException('network', 'AI 服务响应超时，请稍后重试');
    } catch (error) {
      throw AiHttpException(
          'network', '无法连接 AI 服务，请检查网络与接口地址', error.toString());
    }

    if (response.statusCode != 200) {
      throw _mapStatusError(response);
    }

    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        throw const AiHttpException('parse', 'AI 服务返回了非预期的数据格式');
      }
      return Map<String, dynamic>.from(decoded);
    } on AiHttpException {
      rethrow;
    } catch (error) {
      throw AiHttpException('parse', 'AI 服务返回的内容无法解析', error.toString());
    }
  }

  Future<http.Response> _send(
    Uri uri,
    Map<String, String> headers,
    String body,
  ) async {
    // IOClient 从 package:http/io_client.dart 导出（http.dart 主库不含）
    final client = IOClient(HttpClient()..connectionTimeout = connectTimeout);
    try {
      return await client
          .post(uri, headers: headers, body: body)
          .timeout(readTimeout);
    } finally {
      client.close();
    }
  }

  /// 把 HTTP 状态码转成可操作的中文提示。
  AiHttpException _mapStatusError(http.Response response) {
    final detail = _extractErrorMessage(response);
    return switch (response.statusCode) {
      401 || 403 => AiHttpException('auth', 'API Key 无效或没有访问权限', detail),
      404 => AiHttpException(
          'http_status', '接口地址或模型不存在，请检查接口地址与模型 ID', detail),
      429 => AiHttpException('rate_limited', '请求过于频繁，请稍后重试', detail),
      >= 500 => AiHttpException(
          'http_status', 'AI 服务暂时不可用（HTTP ${response.statusCode}）', detail),
      _ => AiHttpException(
          'http_status', '请求失败（HTTP ${response.statusCode}）', detail),
    };
  }

  /// 尽量从错误响应体里取出服务方的原始说明，取不到就返回原始文本。
  String _extractErrorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] != null) {
          return error['message'].toString();
        }
        if (decoded['message'] != null) return decoded['message'].toString();
      }
    } catch (_) {
      // 错误体不是 JSON 时回退原始文本
    }
    final body = response.body.trim();
    return body.length > 300 ? body.substring(0, 300) : body;
  }
}

// ================= Anthropic Messages =================

class AnthropicClient extends AiClient {
  AnthropicClient({super.sender});

  @override
  Future<AiChatResponse> chat(
    AiProvider provider,
    AiModel model,
    AiChatRequest request,
  ) async {
    final uri = AiClient.resolveEndpoint(provider.baseUrl, '/v1/messages');
    final headers = {
      'content-type': 'application/json',
      'x-api-key': provider.apiKey,
      'anthropic-version': '2023-06-01',
      ...provider.parseExtraHeaders(),
    };
    final json = await post(uri, headers, buildBody(model, request));
    return parseResponse(json);
  }

  /// 构造 Anthropic 请求体。system 是顶层字段，不放进 messages。
  @visibleForTesting
  static Map<String, dynamic> buildBody(AiModel model, AiChatRequest request) {
    // 无图片时 content 直接发字符串，省去数组包装的 token
    final Object content = request.images.isEmpty
        ? request.userText
        : [
            for (final image in request.images)
              {
                'type': 'image',
                'source': {
                  'type': 'base64',
                  'media_type': image.mediaType,
                  'data': image.base64Data,
                },
              },
            {'type': 'text', 'text': request.userText},
          ];
    return {
      'model': model.id,
      'max_tokens': AiClient.maxOutputTokens,
      'system': request.systemPrompt,
      'messages': [
        {'role': 'user', 'content': content},
      ],
    };
  }

  /// 提取 content 数组里全部 type == text 的块。
  @visibleForTesting
  static AiChatResponse parseResponse(Map<String, dynamic> json) {
    // 安全策略拦截时 content 为空，必须明确报错，否则界面只会显示空结果
    if (json['stop_reason'] == 'refusal') {
      throw const AiHttpException(
          'refused', 'AI 拒绝了本次识别请求，请调整输入内容后重试');
    }
    final buffer = StringBuffer();
    final content = json['content'];
    if (content is List) {
      for (final block in content) {
        if (block is Map && block['type'] == 'text') {
          buffer.write(block['text']?.toString() ?? '');
        }
      }
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw const AiHttpException('parse', 'AI 没有返回任何文本内容');
    }
    final usage = json['usage'];
    return AiChatResponse(
      text: text,
      inputTokens: usage is Map ? _asIntOrNull(usage['input_tokens']) : null,
      outputTokens: usage is Map ? _asIntOrNull(usage['output_tokens']) : null,
    );
  }
}

// ================= OpenAI Chat Completions =================

class OpenAiChatClient extends AiClient {
  OpenAiChatClient({super.sender});

  @override
  Future<AiChatResponse> chat(
    AiProvider provider,
    AiModel model,
    AiChatRequest request,
  ) async {
    final uri =
        AiClient.resolveEndpoint(provider.baseUrl, '/v1/chat/completions');
    final headers = {
      'content-type': 'application/json',
      'authorization': 'Bearer ${provider.apiKey}',
      ...provider.parseExtraHeaders(),
    };
    final json = await post(uri, headers, buildBody(model, request));
    return parseResponse(json);
  }

  /// 构造 Chat Completions 请求体。system 作为独立的一条消息。
  @visibleForTesting
  static Map<String, dynamic> buildBody(AiModel model, AiChatRequest request) {
    final Object content = request.images.isEmpty
        ? request.userText
        : [
            for (final image in request.images)
              {
                'type': 'image_url',
                'image_url': {'url': image.dataUrl},
              },
            {'type': 'text', 'text': request.userText},
          ];
    return {
      'model': model.id,
      'max_tokens': AiClient.maxOutputTokens,
      'messages': [
        {'role': 'system', 'content': request.systemPrompt},
        {'role': 'user', 'content': content},
      ],
    };
  }

  /// 取 choices[0].message.content。
  /// 该字段在纯文本对话里是字符串、在部分实现里是内容块数组，两种都要兼容。
  @visibleForTesting
  static AiChatResponse parseResponse(Map<String, dynamic> json) {
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const AiHttpException('parse', 'AI 没有返回任何回复内容');
    }
    final first = choices.first;
    final message = first is Map ? first['message'] : null;
    final content = message is Map ? message['content'] : null;

    final text = _flattenContent(content).trim();
    if (text.isEmpty) {
      throw const AiHttpException('parse', 'AI 没有返回任何文本内容');
    }
    final usage = json['usage'];
    return AiChatResponse(
      text: text,
      inputTokens: usage is Map ? _asIntOrNull(usage['prompt_tokens']) : null,
      outputTokens:
          usage is Map ? _asIntOrNull(usage['completion_tokens']) : null,
    );
  }

  static String _flattenContent(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final block in content) {
        if (block is Map && block['type'] == 'text') {
          buffer.write(block['text']?.toString() ?? '');
        } else if (block is String) {
          buffer.write(block);
        }
      }
      return buffer.toString();
    }
    return '';
  }
}

// ================= OpenAI Responses =================

class OpenAiResponsesClient extends AiClient {
  OpenAiResponsesClient({super.sender});

  @override
  Future<AiChatResponse> chat(
    AiProvider provider,
    AiModel model,
    AiChatRequest request,
  ) async {
    final uri = AiClient.resolveEndpoint(provider.baseUrl, '/v1/responses');
    final headers = {
      'content-type': 'application/json',
      'authorization': 'Bearer ${provider.apiKey}',
      ...provider.parseExtraHeaders(),
    };
    final json = await post(uri, headers, buildBody(model, request));
    return parseResponse(json);
  }

  /// 构造 Responses 请求体。系统提示走顶层 instructions，
  /// 输入块的类型名与 Chat Completions 不同（input_text / input_image）。
  @visibleForTesting
  static Map<String, dynamic> buildBody(AiModel model, AiChatRequest request) {
    // 无图片时 input 允许直接传字符串
    final Object input = request.images.isEmpty
        ? request.userText
        : [
            {
              'role': 'user',
              'content': [
                for (final image in request.images)
                  {'type': 'input_image', 'image_url': image.dataUrl},
                {'type': 'input_text', 'text': request.userText},
              ],
            },
          ];
    return {
      'model': model.id,
      'instructions': request.systemPrompt,
      'max_output_tokens': AiClient.maxOutputTokens,
      'input': input,
    };
  }

  /// 优先取便捷字段 output_text；缺失时遍历 output[].content[] 取 output_text 块。
  @visibleForTesting
  static AiChatResponse parseResponse(Map<String, dynamic> json) {
    var text = _flattenOutputText(json['output_text']).trim();

    if (text.isEmpty) {
      final buffer = StringBuffer();
      final output = json['output'];
      if (output is List) {
        for (final item in output) {
          if (item is! Map) continue;
          final content = item['content'];
          if (content is! List) continue;
          for (final block in content) {
            if (block is Map && block['type'] == 'output_text') {
              buffer.write(block['text']?.toString() ?? '');
            }
          }
        }
      }
      text = buffer.toString().trim();
    }

    if (text.isEmpty) {
      throw const AiHttpException('parse', 'AI 没有返回任何文本内容');
    }
    final usage = json['usage'];
    return AiChatResponse(
      text: text,
      inputTokens: usage is Map ? _asIntOrNull(usage['input_tokens']) : null,
      outputTokens: usage is Map ? _asIntOrNull(usage['output_tokens']) : null,
    );
  }

  /// output_text 一般是字符串，少数实现返回字符串数组。
  static String _flattenOutputText(Object? value) {
    if (value is String) return value;
    if (value is List) return value.map((e) => e?.toString() ?? '').join();
    return '';
  }
}

// ================= 工厂 =================

class AiClientFactory {
  /// 按协议格式创建客户端。[sender] 仅测试注入。
  static AiClient forProtocol(
    AiProviderProtocol protocol, {
    AiHttpSender? sender,
  }) {
    return switch (protocol) {
      AiProviderProtocol.anthropic => AnthropicClient(sender: sender),
      AiProviderProtocol.openaiChat => OpenAiChatClient(sender: sender),
      AiProviderProtocol.openaiResponses => OpenAiResponsesClient(sender: sender),
    };
  }
}

int? _asIntOrNull(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}
