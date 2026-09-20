import 'idb_factory.dart';
import 'repository_path.dart' as path;
import '../core/repository.dart';
import '../data/idb_repository.dart';
import '../data/json_repository.dart';

/// 平台默认持久化仓库：Web 用 IndexedDB，原生用 JSON 文件（原子写）。
Future<Repository> openDefaultRepository() async {
  final webFactory = platformIdbFactory();
  if (webFactory != null) {
    final repo = IdbRepository(webFactory);
    await repo.init();
    return repo;
  }
  final repo = JsonFileRepository(await path.defaultJsonPath());
  await repo.init();
  return repo;
}
