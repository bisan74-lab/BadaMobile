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

  /// 원본 문자열을 그대로 읽고 쓴다.
  ///
  /// [readJson]은 꺼내면서 바로 `jsonDecode`를 하는데, 수백 KB짜리 캐시는 그
  /// 파싱만으로도 UI 프레임이 끊긴다. 큰 캐시는 이 두 메서드로 문자열만
  /// 주고받고, 파싱은 호출하는 쪽이 백그라운드 아이솔레이트에서 한다.
  String? readString(String key) => _prefs.getString('$_prefix$key');

  Future<void> writeString(String key, String value) async {
    await _prefs.setString('$_prefix$key', value);
  }

  /// [prefix]로 시작하는 캐시 중 [keep]이 false를 준 것을 지운다.
  ///
  /// 날짜가 들어간 키는 그냥 두면 하루에 하나씩 늘어나기만 한다.
  /// SharedPreferences는 앱을 켤 때 저장된 값을 **전부** 메모리로 읽어 오므로,
  /// 큰 캐시가 쌓이면 시작이 점점 느려진다. 그래서 새로 쓸 때마다 정리한다.
  Future<void> pruneStale(
    String prefix, {
    required bool Function(String key) keep,
  }) async {
    final stale = _prefs
        .getKeys()
        .where((k) => k.startsWith('$_prefix$prefix'))
        .map((k) => k.substring(_prefix.length))
        .where((k) => !keep(k))
        .toList();
    for (final key in stale) {
      await _prefs.remove('$_prefix$key');
    }
  }
}

final cacheStoreProvider = Provider<CacheStore>(
  (ref) => CacheStore(ref.watch(sharedPreferencesProvider)),
);
