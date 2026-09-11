import '../core/repository.dart';
import '../data/memory_repository.dart';
import 'repository_boot.dart';

class PlatformServices {
  PlatformServices({required this.repository});

  final Repository repository;

  /// 生产入口默认走持久仓库（Web=IndexedDB，原生=JSON 文件）；测试注入内存库。
  static Future<PlatformServices> boot({bool persistent = true}) async {
    final Repository repository;
    if (persistent) {
      repository = await openDefaultRepository();
    } else {
      final memory = MemoryRepository();
      await memory.init();
      repository = memory;
    }
    return PlatformServices(repository: repository);
  }
}
