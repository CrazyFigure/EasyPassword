/// AI 协议适配层单元测试：请求体构造、响应提取与错误映射。
///
/// 全部通过注入 AiHttpSender 完成，不发真实网络请求。
library;

import 'dart:convert';

import 'package:easypassword/models/ai_config.dart';
import 'package:easypassword/services/ai_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// 记录最近一次请求，供断言检查
class _Recorder {
  Uri? uri;
  Map<String, String>? headers;
  Map<String, dynamic>? body;

  /// 构造一个返回固定响应体的 sender
  AiHttpSender responding(Object responseJson, {int status = 200}) {
    return (Uri target, {required Map<String, String> headers, required String body}) async {
      uri = target;
      this.headers = headers;
      this.body = jsonDecode(body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode(responseJson),
        status,
        headers: {'content-type': 'application/json'},
      );
    };
  }
}

AiProvider _provider(AiProviderProtocol protocol,
        {List<String> extraHeaders = const []}) =>
    AiProvider(
      id: 'p1',
      name: '测试接入点',
      protocol: protocol,
      baseUrl: 'https://example.com',
      apiKey: 'test-key',
      models: const [AiModel(id: 'test-model', supportsVision: true)],
      extraHeaders: extraHeaders,
    );

const _model = AiModel(id: 'test-model', supportsVision: true);

final _image = AiImageInput(
  bytes: Uint8List.fromList([1, 2, 3, 4]),
  mediaType: 'image/png',
  fileName: 'shot.png',
);

void main() {
  group('Anthropic Messages', () {
    test('无图片时 content 直接是字符串，system 在顶层', () {
      final body = AnthropicClient.buildBody(
        _model,
        const AiChatRequest(systemPrompt: 'SYS', userText: '请识别'),
      );
      expect(body['model'], 'test-model');
      expect(body['system'], 'SYS');
      final messages = body['messages'] as List;
      expect((messages.single as Map)['content'], '请识别');
    });

    test('有图片时按 base64 source 结构携带，且文本块在图片之后', () {
      final body = AnthropicClient.buildBody(
        _model,
        AiChatRequest(
            systemPrompt: 'SYS', userText: '请识别', images: [_image]),
      );
      final content =
          ((body['messages'] as List).single as Map)['content'] as List;
      final imageBlock = content.first as Map;
      expect(imageBlock['type'], 'image');
      final source = imageBlock['source'] as Map;
      expect(source['type'], 'base64');
      expect(source['media_type'], 'image/png');
      expect(source['data'], base64Encode(_image.bytes));
      expect((content.last as Map)['type'], 'text');
    });

    test('请求头带 x-api-key 与 anthropic-version，并合并附加头', () async {
      final recorder = _Recorder();
      await AnthropicClient(sender: recorder.responding({
        'content': [
          {'type': 'text', 'text': '{}'}
        ]
      })).chat(
        _provider(AiProviderProtocol.anthropic,
            extraHeaders: const ['X-Gateway: proxy-1']),
        _model,
        const AiChatRequest(systemPrompt: 'SYS', userText: 'hi'),
      );
      expect(recorder.uri.toString(), 'https://example.com/v1/messages');
      expect(recorder.headers!['x-api-key'], 'test-key');
      expect(recorder.headers!['anthropic-version'], '2023-06-01');
      expect(recorder.headers!['X-Gateway'], 'proxy-1');
    });

    test('多个 text 块按序拼接', () {
      final response = AnthropicClient.parseResponse({
        'content': [
          {'type': 'text', 'text': '前半'},
          {'type': 'thinking', 'text': '不应出现'},
          {'type': 'text', 'text': '后半'},
        ],
        'usage': {'input_tokens': 12, 'output_tokens': 34},
      });
      expect(response.text, '前半后半');
      expect(response.inputTokens, 12);
      expect(response.outputTokens, 34);
    });

    test('安全策略拒绝时抛 refused 而不是返回空文本', () {
      expect(
        () => AnthropicClient.parseResponse({
          'stop_reason': 'refusal',
          'content': <Object>[],
        }),
        throwsA(isA<AiHttpException>()
            .having((e) => e.code, 'code', 'refused')),
      );
    });

    test('没有任何文本块时抛 parse', () {
      expect(
        () => AnthropicClient.parseResponse({'content': <Object>[]}),
        throwsA(isA<AiHttpException>().having((e) => e.code, 'code', 'parse')),
      );
    });
  });

  group('OpenAI Chat Completions', () {
    test('system 作为独立消息，无图片时 content 是字符串', () {
      final body = OpenAiChatClient.buildBody(
        _model,
        const AiChatRequest(systemPrompt: 'SYS', userText: '请识别'),
      );
      final messages = body['messages'] as List;
      expect((messages.first as Map)['role'], 'system');
      expect((messages.first as Map)['content'], 'SYS');
      expect((messages.last as Map)['content'], '请识别');
    });

    test('有图片时使用 image_url 的 data URL 形式', () {
      final body = OpenAiChatClient.buildBody(
        _model,
        AiChatRequest(
            systemPrompt: 'SYS', userText: '请识别', images: [_image]),
      );
      final content = ((body['messages'] as List).last as Map)['content'] as List;
      final imageBlock = content.first as Map;
      expect(imageBlock['type'], 'image_url');
      expect(
        (imageBlock['image_url'] as Map)['url'],
        startsWith('data:image/png;base64,'),
      );
    });

    test('认证头使用 Bearer', () async {
      final recorder = _Recorder();
      await OpenAiChatClient(sender: recorder.responding({
        'choices': [
          {
            'message': {'content': 'ok'}
          }
        ]
      })).chat(
        _provider(AiProviderProtocol.openaiChat),
        _model,
        const AiChatRequest(systemPrompt: 'SYS', userText: 'hi'),
      );
      expect(recorder.uri.toString(),
          'https://example.com/v1/chat/completions');
      expect(recorder.headers!['authorization'], 'Bearer test-key');
    });

    test('content 为字符串时直接取用', () {
      final response = OpenAiChatClient.parseResponse({
        'choices': [
          {
            'message': {'content': '纯文本回复'}
          }
        ],
      });
      expect(response.text, '纯文本回复');
    });

    test('content 为内容块数组时拼接 text 块', () {
      final response = OpenAiChatClient.parseResponse({
        'choices': [
          {
            'message': {
              'content': [
                {'type': 'text', 'text': 'A'},
                {'type': 'text', 'text': 'B'},
              ]
            }
          }
        ],
      });
      expect(response.text, 'AB');
    });

    test('choices 为空时抛 parse', () {
      expect(
        () => OpenAiChatClient.parseResponse({'choices': <Object>[]}),
        throwsA(isA<AiHttpException>().having((e) => e.code, 'code', 'parse')),
      );
    });
  });

  group('OpenAI Responses', () {
    test('系统提示走 instructions，无图片时 input 是字符串', () {
      final body = OpenAiResponsesClient.buildBody(
        _model,
        const AiChatRequest(systemPrompt: 'SYS', userText: '请识别'),
      );
      expect(body['instructions'], 'SYS');
      expect(body['input'], '请识别');
      expect(body['max_output_tokens'], isNotNull);
    });

    test('有图片时使用 input_image 与 input_text 块', () {
      final body = OpenAiResponsesClient.buildBody(
        _model,
        AiChatRequest(
            systemPrompt: 'SYS', userText: '请识别', images: [_image]),
      );
      final content =
          ((body['input'] as List).single as Map)['content'] as List;
      expect((content.first as Map)['type'], 'input_image');
      expect((content.first as Map)['image_url'],
          startsWith('data:image/png;base64,'));
      expect((content.last as Map)['type'], 'input_text');
    });

    test('优先使用 output_text 便捷字段', () {
      final response = OpenAiResponsesClient.parseResponse({
        'output_text': '便捷字段内容',
        'output': [
          {
            'content': [
              {'type': 'output_text', 'text': '不该被用到'}
            ]
          }
        ],
      });
      expect(response.text, '便捷字段内容');
    });

    test('缺少 output_text 时遍历 output 数组兜底', () {
      final response = OpenAiResponsesClient.parseResponse({
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': '第一段'},
              {'type': 'refusal', 'text': '忽略'},
              {'type': 'output_text', 'text': '第二段'},
            ]
          }
        ],
      });
      expect(response.text, '第一段第二段');
    });
  });

  group('错误映射', () {
    Future<AiHttpException> capture(int status, {Object? body}) async {
      final recorder = _Recorder();
      try {
        await AnthropicClient(
          sender: recorder.responding(
            body ?? {'error': {'message': '服务端说明'}},
            status: status,
          ),
        ).chat(
          _provider(AiProviderProtocol.anthropic),
          _model,
          const AiChatRequest(systemPrompt: 'S', userText: 'u'),
        );
      } on AiHttpException catch (error) {
        return error;
      }
      fail('状态码 $status 应当抛出 AiHttpException');
    }

    test('401 映射为 auth', () async {
      final error = await capture(401);
      expect(error.code, 'auth');
      expect(error.message, contains('API Key'));
      expect(error.detail, '服务端说明');
    });

    test('403 同样映射为 auth', () async {
      expect((await capture(403)).code, 'auth');
    });

    test('404 提示检查地址与模型', () async {
      final error = await capture(404);
      expect(error.code, 'http_status');
      expect(error.message, contains('模型'));
    });

    test('429 映射为 rate_limited', () async {
      expect((await capture(429)).code, 'rate_limited');
    });

    test('500 映射为 http_status 并提示服务不可用', () async {
      final error = await capture(500);
      expect(error.code, 'http_status');
      expect(error.message, contains('不可用'));
    });

    test('网络异常映射为 network', () async {
      AiHttpException? captured;
      try {
        await AnthropicClient(
          sender: (uri, {required headers, required body}) =>
              throw const SocketExceptionStub(),
        ).chat(
          _provider(AiProviderProtocol.anthropic),
          _model,
          const AiChatRequest(systemPrompt: 'S', userText: 'u'),
        );
      } on AiHttpException catch (error) {
        captured = error;
      }
      expect(captured?.code, 'network');
    });
  });

  group('地址拼接', () {
    test('容忍结尾多余斜杠', () {
      final uri = AiClient.resolveEndpoint('https://a.com///', '/v1/messages');
      expect(uri.toString(), 'https://a.com/v1/messages');
    });

    test('空地址给出可操作提示', () {
      expect(
        () => AiClient.resolveEndpoint('   ', '/v1/messages'),
        throwsA(isA<AiHttpException>()),
      );
    });

    test('缺少协议头的地址被拒绝', () {
      expect(
        () => AiClient.resolveEndpoint('a.com', '/v1/messages'),
        throwsA(isA<AiHttpException>()),
      );
    });
  });

  group('接入点模型', () {
    test('附加请求头解析忽略非法行', () {
      final provider = _provider(
        AiProviderProtocol.anthropic,
        extraHeaders: const ['A: 1', '没有冒号', ': 空键', 'B:2'],
      );
      final headers = provider.parseExtraHeaders();
      expect(headers, {'A': '1', 'B': '2'});
    });

    test('未知协议 id 回退 anthropic', () {
      expect(AiProviderProtocol.fromId('unknown-future'),
          AiProviderProtocol.anthropic);
      expect(AiProviderProtocol.fromId(null), AiProviderProtocol.anthropic);
      expect(AiProviderProtocol.fromId('openai_chat'),
          AiProviderProtocol.openaiChat);
    });

    test('模型与接入点的展示名在为空时回退', () {
      expect(const AiModel(id: 'm-1').label, 'm-1');
      expect(const AiModel(id: 'm-1', displayName: ' 名称 ').label, '名称');
      const unnamed = AiProvider(
        id: 'x',
        name: '  ',
        protocol: AiProviderProtocol.openaiChat,
        baseUrl: 'https://a.com',
        apiKey: 'k',
      );
      expect(unnamed.label, AiProviderProtocol.openaiChat.label);
    });

    test('配置序列化往返保持一致', () {
      final config = AiProviderConfig(providers: [
        _provider(AiProviderProtocol.openaiResponses,
            extraHeaders: const ['H: v']),
      ]);
      final restored =
          AiProviderConfig.fromJson(jsonDecode(jsonEncode(config.toJson())));
      final provider = restored.providers.single;
      expect(provider.protocol, AiProviderProtocol.openaiResponses);
      expect(provider.apiKey, 'test-key');
      expect(provider.models.single.id, 'test-model');
      expect(provider.models.single.supportsVision, isTrue);
      expect(provider.extraHeaders, ['H: v']);
    });

    test('字段缺失或类型错误时回退默认值而不抛异常', () {
      final provider = AiProvider.fromJson({
        'id': 'x',
        'models': 'not-a-list',
        'protocol': 42,
      });
      expect(provider.protocol, AiProviderProtocol.anthropic);
      expect(provider.models, isEmpty);
      expect(provider.apiKey, '');
    });
  });
}

/// 模拟连接层异常，避免测试直接依赖 dart:io
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'connection refused';
}
