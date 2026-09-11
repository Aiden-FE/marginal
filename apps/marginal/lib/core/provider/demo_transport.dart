import 'dart:async';

import 'provider_transport.dart';

typedef DemoResponder = FutureOr<ChatResponse> Function(ChatRequest request);

class DemoTransport implements ProviderTransport {
  DemoTransport({List<ChatResponse> responses = const [], this.fallback})
    : _script = responses
          .map<DemoResponder>(
            (r) =>
                (_) => r,
          )
          .toList();
  DemoTransport.responder(DemoResponder responder, {this.fallback})
    : _script = [responder];
  final List<DemoResponder> _script;
  final DemoResponder? fallback;
  final requests = <ChatRequest>[];
  int get requestCount => requests.length;
  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();
  @override
  Future<ChatResponse> complete(ChatRequest request) async {
    requests.add(request);
    if (_script.isNotEmpty) return await _script.removeAt(0)(request);
    if (fallback != null) return await fallback!(request);
    final text =
        request.messages
            .lastWhere(
              (m) => m.role == ChatRole.user,
              orElse: () => ChatMessage(role: ChatRole.user, content: ''),
            )
            .content ??
        '';
    return ChatResponse.text(text);
  }
}
