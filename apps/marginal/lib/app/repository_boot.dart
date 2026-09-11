import 'idb_factory.dart';
import '../core/repository.dart';
import '../data/idb_repository.dart';
import '../data/json_repository.dart';

/// 平台默认持久化仓库：Web 用 IndexedDB，原生用 JSON 文件（原子写）。
/// 桌面/移动后续可无缝换 SQLite 驱动（同一 Repository 契约）。
Future<Repository> openDefaultRepository() async {
  final webFactory = platformIdbFactory();
  if (webFactory != null) {
    final repo = IdbRepository(webFactory);
    await repo.init();
    return repo;
  }
  final repo = JsonFileRepository(_defaultJsonPath());
  await repo.init();
  return repo;
}

String _defaultJsonPath() => '.marginal/library.json';
