import 'package:marginal/app/ai/ai_services.dart';

/// 固定返回预制实体列表的假提取服务。
class FakeExtractionService implements EntityExtractionService {
  FakeExtractionService([this.results = const []]);

  List<ExtractedEntity> results;
  int calls = 0;
  String? lastWorkId;
  String? lastChapterId;

  @override
  Future<List<ExtractedEntity>> extract({
    required String workId,
    required String chapterId,
  }) async {
    calls++;
    lastWorkId = workId;
    lastChapterId = chapterId;
    return results;
  }
}

/// 固定返回固定 blobId 的假插图生成服务。
class FakeGenerationService implements IllustrationGenerationService {
  FakeGenerationService(this.blobId);

  final String blobId;
  int calls = 0;
  final List<String> prompts = [];

  @override
  Future<String> generate({
    required String workId,
    required String prompt,
    String? referenceBlobId,
  }) async {
    calls++;
    prompts.add(prompt);
    return blobId;
  }
}
