import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/env.dart';
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

  Future<AppGateConfig> fetch() async {
    if (Env.forceUpgradeConfigUrl.isEmpty) return AppGateConfig.disabled;
    try {
      final uri = Uri.parse(Env.forceUpgradeConfigUrl);
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return AppGateConfig.disabled;
      // 서버가 charset을 명시하지 않아도(기본 latin1로 오판되어 한글이
      // 깨지는 일이 없도록) 항상 UTF-8로 직접 디코딩한다.
      final json = jsonDecode(utf8.decode(res.bodyBytes));
      if (json is! Map<String, dynamic>) return AppGateConfig.disabled;
      return AppGateConfig.fromJson(json);
    } catch (_) {
      return AppGateConfig.disabled;
    }
  }
}
