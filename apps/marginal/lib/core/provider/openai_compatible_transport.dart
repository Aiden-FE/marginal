import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'provider_transport.dart';

class HttpJsonResponse {
  const HttpJsonResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

/// POST JSON seam：生产用 [DefaultHttpJsonClient]（package:http，三端可用），测试注入 fake。
abstract interface class HttpJsonClient {
  Future<HttpJsonResponse> post(
    Uri uri,
    Map<String, String> headers,
    Object body,
  );

  /// Implementations may override this for probes; the fallback keeps test seams
  /// source-compatible with the original POST-only contract.
  Future<HttpJsonResponse> get(Uri uri, Map<String, String> headers) =>
      post(uri, headers, const {});
}

class DefaultHttpJsonClient implements HttpJsonClient {
  DefaultHttpJsonClient({
    http.Client? inner,
    this.timeout = const Duration(seconds: 120),
  }) : _inner = inner ?? http.Client();
  final http.Client _inner;
  final Duration timeout;

  @override
  Future<HttpJsonResponse> get(Uri uri, Map<String, String> headers) async {
    final response = await _inner.get(uri, headers: headers).timeout(timeout);
    return HttpJsonResponse(response.statusCode, response.body);
  }

  @override
  Future<HttpJsonResponse> post(
    Uri uri,
    Map<String, String> headers,
    Object body,
  ) async {
    final response = await _inner
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(timeout);
    return HttpJsonResponse(response.statusCode, response.body);
  }
}

class OpenAICompatibleTransport implements ProviderTransport {
  OpenAICompatibleTransport({
    required String baseUrl,
    required this.apiKey,
    required this.model,
    this.organization,
    Map<String, String> headers = const {},
    this.client,
  }) : baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       headers = Map.unmodifiable(headers);
  final String baseUrl, apiKey, model;
  final String? organization;
  final Map<String, String> headers;
  final HttpJsonClient? client;

  @override
  ProviderCapabilities get capabilities => _capabilities;
  ProviderCapabilities _capabilities = const ProviderCapabilities();

  /// 最小 chat+tools 探测：发送一条只带一个工具的请求。
  /// 探测失败（网络错误或 4xx/5xx 拒绝 tools 参数）时降级为
  /// JSON action 协议（supportsTools=false, jsonActionFallback=true），
  /// 之后 [AgentRuntime] 会自动改走 JSON action 降级路径。
  Future<ProviderCapabilities> probeCapabilities() async {
    final probe = ChatRequest(
      messages: [ChatMessage(role: ChatRole.user, content: 'ping')],
      tools: [ToolSpec(name: 'ping')],
    );
    ProviderCapabilities probed = const ProviderCapabilities();
    try {
      await complete(probe);
    } on Object {
      probed = const ProviderCapabilities(
        supportsTools: false,
        jsonActionFallback: true,
      );
    }
    _capabilities = probed;
    return probed;
  }

  @override
  Future<ChatResponse> complete(ChatRequest request) async {
    final uri = Uri.parse('$baseUrl/chat/completions');
    final requestHeaders = <String, String>{
      'authorization': 'Bearer $apiKey',
      'content-type': 'application/json',
      ...headers,
    };
    if (organization != null) {
      requestHeaders['openai-organization'] = organization!;
    }
    try {
      final response = await (client ?? DefaultHttpJsonClient()).post(
        uri,
        requestHeaders,
        {...request.toJson(), 'model': request.model ?? model},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String message = response.body;
        try {
          message =
              ((jsonDecode(response.body) as Map)['error'] as Map?)?['message']
                  as String? ??
              message;
        } catch (_) {}
        throw ProviderException(
          message,
          statusCode: response.statusCode,
          retryable: response.statusCode == 429 || response.statusCode >= 500,
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw const FormatException('Provider response is not an object');
      }
      return ChatResponse.fromJson(decoded.cast<String, Object?>());
    } on ProviderException {
      rethrow;
    } on Object catch (error) {
      throw ProviderException(
        'Network or decoding error: $error',
        retryable: true,
        cause: error,
      );
    }
  }

  /// 连通性诊断：GET /models，能拿到任何 HTTP 响应即视为可达。
  Future<String> diagnose() async {
    final uri = Uri.parse('$baseUrl/models');
    try {
      final response =
          await (client ??
                  DefaultHttpJsonClient(timeout: const Duration(seconds: 15)))
              .get(uri, {'authorization': 'Bearer $apiKey'});
      return response.statusCode < 500 ? 'direct' : 'needs-proxy';
    } on Object {
      return 'needs-proxy';
    }
  }
}
