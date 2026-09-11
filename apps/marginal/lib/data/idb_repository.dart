import 'dart:convert';

import 'package:idb_shim/idb_shim.dart';

import 'memory_repository.dart';
import 'snapshot_persistence.dart';

/// H5 IndexedDB 驱动：与 JSON 文件驱动同一份序列化根，存进单一 kv 记录。
/// 测试注入 idbFactoryMemory 即可在 VM 跑同一契约。
class IdbRepository extends MemoryRepository with SnapshotPersistence {
  IdbRepository(this.factory);
  final IdbFactory factory;

  static const dbName = 'marginal';
  static const storeName = 'kv';
  static const rootKey = 'root';

  Database? _db;

  @override
  String get engine => 'indexeddb';

  @override
  Future<void> init() async {
    _db = await factory.open(
      dbName,
      version: 1,
      onUpgradeNeeded: (event) {
        event.database.createObjectStore(storeName);
      },
    );
    final raw = await _read();
    if (raw == null) return;
    await loadSnapshotRoot(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<String?> _read() async {
    final txn = _db!.transaction(storeName, 'readonly');
    final value = await txn.objectStore(storeName).getObject(rootKey);
    await txn.completed;
    return value as String?;
  }

  @override
  Future<void> persist() async {
    if (isLoadingSnapshot || _db == null) return;
    final txn = _db!.transaction(storeName, 'readwrite');
    await txn
        .objectStore(storeName)
        .put(jsonEncode(await snapshotRoot()), rootKey);
    await txn.completed;
  }
}
