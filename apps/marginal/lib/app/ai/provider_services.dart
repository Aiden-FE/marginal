import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/provider/openai_compatible_transport.dart';
import '../../core/provider/provider_transport.dart';
import '../../core/repository.dart';
import '../../core/types.dart';
import '../ids.dart';
import '../provider_store.dart';
import 'ai_services.dart';

class ProviderEntityExtractionService implements EntityExtractionService {
  ProviderEntityExtractionService({
    required this.repository,
    required this.provider,
  });
  final Repository repository;
  final ProviderEntry provider;
  @override
  Future<List<ExtractedEntity>> extract({
    required String workId,
    required String chapterId,
  }) async {
    final text = await repository.getChapterText(chapterId);
    if (provider.id == 'demo') return const [];
    final transport = OpenAICompatibleTransport(
      baseUrl: provider.baseUrl,
      apiKey: provider.apiKey,
      model: provider.model,
    );
    final found = <ExtractedEntity>[];
    for (var start = 0; start < text.length; start += 6000) {
      final chunk = text.substring(start, (start + 6000).clamp(0, text.length));
      final response = await transport.complete(
        ChatRequest(
          model: provider.model,
          temperature: 0,
          messages: [
            ChatMessage(
              role: ChatRole.system,
              content: '从小说正文提取人物、场景、物品。只输出 JSON：{"cards":[{"kind":"character|scene|item","name":"名称","aliases":[],"attributes":{}}]}',
            ),
            ChatMessage(role: ChatRole.user, content: chunk),
          ],
        ),
      );
      final match = RegExp(r'\{[\s\S]*\}')
          .firstMatch(response.message.content ?? '');
      if (match == null) continue;
      try {
        final root = jsonDecode(match.group(0)!) as Map<String, dynamic>;
        for (final raw in (root['cards'] as List? ?? const [])) {
          final j = Map<String, dynamic>.from(raw as Map);
          final kind = parseEntityKind(j['kind'] ?? 'character');
          final name = (j['name'] ?? '').toString().trim();
          if (name.isEmpty ||
              found.any((e) => e.kind == kind && e.name == name)) {
            continue;
          }
          found.add(
            ExtractedEntity(
              kind: kind,
              name: name,
              aliases: (j['aliases'] as List? ?? const [])
                  .map((e) => e.toString())
                  .toList(),
              attributes: Map<String, String>.from(
                j['attributes'] as Map? ?? {},
              ),
            ),
          );
        }
      } catch (_) {}
    }
    return found;
  }
}

class ProviderIllustrationGenerationService
    implements IllustrationGenerationService {
  ProviderIllustrationGenerationService({
    required this.repository,
    required this.provider,
    http.Client? client,
  }) : _client = client ?? http.Client();
  final Repository repository;
  final ProviderEntry provider;
  final http.Client _client;
  @override
  Future<String> generate({
    required String workId,
    required String prompt,
    String? referenceBlobId,
  }) async {
    Uint8List bytes;
    if (provider.id == 'demo') {
      bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
    } else {
      final base = provider.baseUrl.replaceAll(RegExp(r'/+$'), '');
      final response = await _client.post(
        Uri.parse('$base/images/generations'),
        headers: {
          'Authorization': 'Bearer ${provider.apiKey}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': provider.model,
          'prompt': prompt,
          'n': 1,
          'response_format': 'b64_json',
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError('图片生成失败 ${response.statusCode}');
      }
      final root = jsonDecode(response.body) as Map<String, dynamic>;
      final item = (root['data'] as List).first as Map;
      final b64 = item['b64_json'] as String?;
      if (b64 == null) throw const FormatException('图片接口未返回 b64_json');
      bytes = base64Decode(b64);
    }
    final id = newId('blob');
    await repository.putBlob(
      BlobRec(
        id: id,
        workId: workId,
        storageKey: '$workId/$id',
        kind: 'image',
        mime: 'image/png',
        byteSize: bytes.length,
      ),
      bytes,
    );
    return id;
  }
}
