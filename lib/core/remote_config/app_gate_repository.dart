import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/env.dart';
import '../storage/cache_store.dart';
import 'app_gate_config.dart';

/// [Env.forceUpgradeConfigUrl]에서 강제 업데이트 게이트 설정을 받아온다.
///
/// 네트워크 실패·타임아웃·잘못된 응답 등 어떤 이유로든 설정을 확인할 수
/// 없으면 [AppGateConfig.disabled]를 돌려준다 — 오프라인이거나 설정
/// 서버에 문제가 있다고 해서 앱 실행을 막아서는 안 되기 때문이다.
class AppGateRepository {
  AppGateRepository({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 5);

  /// 기기에 저장해 두는 마지막 설정의 캐시 키.
  static const cacheKey = 'app_gate';

  /// 설정을 받아오되, **판단할 수 없으면 null**을 돌려준다.
  ///
  /// [fetch]와 달리 "서버가 막지 말라고 했다"와 "확인하지 못했다"를 구분한다.
  /// 이 구분이 없으면 네트워크가 한 번 삐끗했을 때 캐시에 저장된 차단 설정을
  /// `disabled`로 덮어써, 막아야 할 기기가 풀려 버린다.
  Future<AppGateConfig?> fetchOrNull() async {
    if (Env.forceUpgradeConfigUrl.isEmpty) return null;
    try {
      final uri = Uri.parse(Env.forceUpgradeConfigUrl);
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return null;
      // 서버가 charset을 명시하지 않아도(기본 latin1로 오판되어 한글이
      // 깨지는 일이 없도록) 항상 UTF-8로 직접 디코딩한다.
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is! Map<String, dynamic>) return null;
      return AppGateConfig.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// 설정을 받아오되, 어떤 이유로든 확인할 수 없으면 [AppGateConfig.disabled].
  Future<AppGateConfig> fetch() async =>
      await fetchOrNull() ?? AppGateConfig.disabled;

  /// 지난 실행에서 저장해 둔 설정. 없거나 손상됐으면 null.
  AppGateConfig? readCached(CacheStore cache) {
    final json = cache.readJson(cacheKey);
    if (json == null) return null;
    try {
      return AppGateConfig.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeCache(CacheStore cache, AppGateConfig config) =>
      cache.writeJson(cacheKey, config.toJson());
}
