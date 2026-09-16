import 'dart:convert';
import 'dart:io';

import 'memory_repository.dart';
import 'snapshot_persistence.dart';

/// JSON 文件驱动：作为原生端可迁移基线，完整持久化 Repository 语义。
class JsonFileRepository extends MemoryRepository with SnapshotPersistence {
  JsonFileRepository(String path) : file = File(path);
  final File file;

  @override
  String get engine => 'json-file';

  @override
  Future<void> init() async {
    if (!await file.exists()) return;
    final root = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    await loadSnapshotRoot(root);
  }

  @override
  Future<void> persist() async {
    if (isLoadingSnapshot) return;
    final tmp = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await tmp.parent.create(recursive: true);
    await tmp.writeAsString(jsonEncode(await snapshotRoot()), flush: true);
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    try {
      await tmp.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await file.exists()) await file.delete();
      if (await backup.exists()) await backup.rename(file.path);
      rethrow;
    }
  }
}
