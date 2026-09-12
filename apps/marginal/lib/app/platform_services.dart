import '../core/repository.dart';
import '../data/memory_repository.dart';
import 'repository_boot.dart';
import 'provider_store.dart';

class PlatformServices {
  PlatformServices({required this.repository, ProviderStore? providerStore})
    : providerStore = providerStore ?? ProviderStore();

  final Repository repository;
  final ProviderStore providerStore;

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
    final services = PlatformServices(repository: repository);
    if (persistent) await services.providerStore.load();
    return services;
  }
}
