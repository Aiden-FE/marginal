import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/provider/openai_compatible_transport.dart';

class ProviderEntry {
  const ProviderEntry({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.diagnostic = 'unknown',
  });
  final String id, name, baseUrl, apiKey, model, diagnostic;
  ProviderEntry copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? diagnostic,
  }) => ProviderEntry(
    id: id,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    diagnostic: diagnostic ?? this.diagnostic,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'diagnostic': diagnostic,
  };
  factory ProviderEntry.fromJson(Map<String, dynamic> j) => ProviderEntry(
    id: j['id'] ?? '',
    name: j['name'] ?? '',
    baseUrl: j['baseUrl'] ?? '',
    apiKey: j['apiKey'] ?? '',
    model: j['model'] ?? '',
    diagnostic: j['diagnostic'] ?? 'unknown',
  );
}

class ProviderStore extends ChangeNotifier {
  ProviderStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'marginal.providers.v2';
  List<ProviderEntry> providers = [
    const ProviderEntry(
      id: 'demo',
      name: '内置演示',
      baseUrl: 'demo://local',
      apiKey: '',
      model: 'demo',
    ),
  ];
  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw != null) {
        final xs = jsonDecode(raw) as List;
        providers = [
          providers.first,
          ...xs.map(
            (e) =>
                ProviderEntry.fromJson(Map<String, dynamic>.from(e as Map))
                    .copyWith(diagnostic: 'unknown'),
          ),
        ];
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> save() async {
    await _storage.write(
      key: _key,
      value: jsonEncode(
        providers.where((p) => p.id != 'demo').map((p) => p.toJson()).toList(),
      ),
    );
    notifyListeners();
  }

  Future<void> upsert(ProviderEntry value) async {
    final i = providers.indexWhere((p) => p.id == value.id);
    if (i < 0) {
      providers = [...providers, value];
    } else {
      providers = [...providers]..[i] = value;
    }
    await save();
  }

  Future<void> remove(String id) async {
    providers = providers.where((p) => p.id == id || p.id == 'demo').toList();
    await save();
  }

  Future<String> diagnose(ProviderEntry p) async {
    if (p.id == 'demo') return 'direct';
    final t = OpenAICompatibleTransport(
      baseUrl: p.baseUrl,
      apiKey: p.apiKey,
      model: p.model,
    );
    final result = await t.diagnose();
    await upsert(p.copyWith(diagnostic: result));
    return result;
  }
}
