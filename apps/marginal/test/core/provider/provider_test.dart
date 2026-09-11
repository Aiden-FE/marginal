import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:marginal/core/provider/provider.dart';

class FakeClient implements HttpJsonClient {
  FakeClient(this.response);
  final HttpJsonResponse response;
  Uri? uri;
  Map<String, String>? headers;
  Object? body;
  @override
  Future<HttpJsonResponse> post(Uri u, Map<String, String> h, Object b) async {
    uri = u;
    headers = h;
    body = b;
    return response;
  }

  @override
  Future<HttpJsonResponse> get(Uri u, Map<String, String> h) async {
    uri = u;
    headers = h;
    return response;
  }
}

void main() {
  test('chat DTO round trips tool calls and usage', () {
    final call = ToolCall(id: '1', name: 'sum', arguments: {'a': 2});
    final msg = ChatMessage(role: ChatRole.assistant, toolCalls: [call]);
    final restored = ChatMessage.fromJson(msg.toJson());
    expect(restored.toolCalls.single.arguments['a'], 2);
    final r = ChatResponse.fromJson({
      'choices': [
        {'message': msg.toJson(), 'finish_reason': 'tool_calls'},
      ],
      'usage': {'prompt_tokens': 1, 'completion_tokens': 2},
    });
    expect(r.usage!.totalTokens, 3);
  });
  test('demo scripts and fallback', () async {
    final d = DemoTransport(responses: [ChatResponse.text('one')]);
    expect(
      (await d.complete(ChatRequest(messages: []))).message.content,
      'one',
    );
    expect(
      (await d.complete(
        ChatRequest(
          messages: [ChatMessage(role: ChatRole.user, content: 'hi')],
        ),
      )).message.content,
      'hi',
    );
    expect(d.requestCount, 2);
  });
  test('openai compatible request and response', () async {
    final fake = FakeClient(
      HttpJsonResponse(
        200,
        jsonEncode({
          'choices': [
            {
              'message': {'role': 'assistant', 'content': 'ok'},
              'finish_reason': 'stop',
            },
          ],
        }),
      ),
    );
    final t = OpenAICompatibleTransport(
      baseUrl: 'https://x/v1/',
      apiKey: 'key',
      model: 'm',
      client: fake,
    );
    final r = await t.complete(
      ChatRequest(
        messages: [ChatMessage(role: ChatRole.user, content: 'hi')],
      ),
    );
    expect(r.message.content, 'ok');
    expect(fake.uri.toString(), 'https://x/v1/chat/completions');
    expect((fake.body as Map)['model'], 'm');
    expect(fake.headers!['authorization'], 'Bearer key');
  });
  test('openai errors classify retryable', () async {
    final fake = FakeClient(
      const HttpJsonResponse(429, '{"error":{"message":"slow"}}'),
    );
    expect(
      () => OpenAICompatibleTransport(
        baseUrl: 'https://x',
        apiKey: 'k',
        model: 'm',
        client: fake,
      ).complete(ChatRequest(messages: [])),
      throwsA(
        isA<ProviderException>().having((e) => e.retryable, 'retryable', true),
      ),
    );
  });
}
