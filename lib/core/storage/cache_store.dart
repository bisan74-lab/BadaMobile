import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'prefs.dart';

/// JSON 기반 로컬 캐시. 오프라인 시 마지막 조회 데이터를 보여주는 용도 (FR-11).
class CacheStore {
  const CacheStore(this._prefs);

  final SharedPreferences _prefs;
  static const _prefix = 'cache_v1_';

  Map<String, dynamic>? readJson(String key) {
    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null; // 손상된 캐시는 없는 것으로 취급
    }
  }

  Future<void> writeJson(String key, Map<String, dynamic> json) async {
    await _prefs.setString('$_prefix$key', jsonEncode(json));
  }
}

final cacheStoreProvider = Provider<CacheStore>(
  (ref) => CacheStore(ref.watch(sharedPreferencesProvider)),
);
