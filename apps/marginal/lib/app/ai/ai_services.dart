/// AI 服务接口：实体提取与插图生成。
///
/// UI 只依赖这些接口；真实实现走用户配置的 Provider，测试用 Demo/fake。
library;
import '../../core/types.dart';

/// 一条待写入的实体卡草稿。
class ExtractedEntity {
  const ExtractedEntity({
    required this.kind,
    required this.name,
    this.aliases = const [],
    this.attributes = const {},
  });
  final EntityKind kind;
  final String name;
  final List<String> aliases;
  final Map<String, String> attributes;
}

/// 实体提取：从章节正文提取实体卡草稿（去重合并由调用方处理）。
abstract interface class EntityExtractionService {
  Future<List<ExtractedEntity>> extract({required String workId, required String chapterId});
}

/// 插图生成：按提示词生成图片并落为 blob，返回 blobId。
abstract interface class IllustrationGenerationService {
  Future<String> generate({
    required String workId,
    required String prompt,
    String? referenceBlobId,
  });
}

/// 任务进度事件（导入/提取/生成共用）。
sealed class AiTaskEvent {
  const AiTaskEvent();
}

class AiTaskProgress extends AiTaskEvent {
  const AiTaskProgress(this.message, this.done, this.total);
  final String message;
  final int done, total;
}

class AiTaskDone<T> extends AiTaskEvent {
  const AiTaskDone(this.value);
  final T value;
}

class AiTaskFailed extends AiTaskEvent {
  const AiTaskFailed(this.error);
  final String error;
}
