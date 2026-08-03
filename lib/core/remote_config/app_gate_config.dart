/// 강제 업데이트 게이트 설정. 공개 데이터 저장소의 `app_gate.json`에서
/// 받아온다(원본 사본은 `public_data/app_gate.json`).
///
/// 막는 방법이 두 가지다.
/// - [minSupportedVersion]: **버전 기준**. 이보다 낮은 버전은 실행을 막는다.
///   새 버전을 Play에 올린 뒤 이 값을 그 버전으로 올리면, 구버전을 쓰던 기기는
///   다음 실행부터 업데이트 안내 화면만 보게 된다. **평소에 쓰는 방법이다.**
/// - [forceUpgrade]: **전체 차단 스위치**. 버전과 무관하게 모두 막는다.
///   서버 데이터 형식을 갈아엎는 등 구버전이 전부 못 쓰게 됐을 때만 쓴다.
class AppGateConfig {
  const AppGateConfig({
    required this.forceUpgrade,
    required this.minSupportedVersion,
    required this.message,
    required this.storeUrl,
  });

  /// true면 버전과 상관없이 앱 실행을 막는다(비상 스위치).
  final bool forceUpgrade;

  /// 실행을 허용하는 **최소 버전**(`0.4.6` 같은 점 구분 문자열).
  /// 비어 있거나 형식이 이상하면 버전 기준 차단을 하지 않는다.
  final String minSupportedVersion;

  /// 안내 화면에 보여줄 메시지.
  final String message;

  /// "업데이트" 버튼을 누르면 열리는 스토어 링크.
  final String storeUrl;

  /// 설정을 못 받아왔을 때(오프라인·서버 오류 등) 쓰는 기본값 — 항상 앱을
  /// 정상 실행시킨다. 강제 업데이트 확인 실패를 이유로 사용자를 막지 않는다.
  static const disabled = AppGateConfig(
    forceUpgrade: false,
    minSupportedVersion: '',
    message: '',
    storeUrl: '',
  );

  factory AppGateConfig.fromJson(Map<String, dynamic> json) => AppGateConfig(
    forceUpgrade: json['forceUpgrade'] as bool? ?? false,
    minSupportedVersion: json['minSupportedVersion'] as String? ?? '',
    message: json['message'] as String? ?? '새 버전으로 업데이트해 주세요.',
    storeUrl: json['storeUrl'] as String? ?? '',
  );

  /// [currentVersion]으로 실행 중인 앱을 막아야 하는가.
  ///
  /// **판단이 애매하면 항상 통과시킨다**(fail-open). 설정 파일에 오타가 나거나
  /// 형식이 바뀌었다고 해서 이미 설치된 앱이 전부 못 켜지면 안 되기 때문이다.
  bool blocks(String currentVersion) {
    if (forceUpgrade) return true;
    final min = _parseVersion(minSupportedVersion);
    final cur = _parseVersion(currentVersion);
    if (min == null || cur == null) return false;
    return _compare(cur, min) < 0;
  }
}

/// `0.4.6` 같은 점 구분 버전을 숫자 목록으로 바꾼다. 숫자가 아닌 조각이
/// 있거나 비어 있으면 null(= 비교하지 않음).
List<int>? _parseVersion(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  // `0.4.6+115`처럼 빌드 번호가 붙어 와도 앞부분만 본다.
  final core = text.split('+').first;
  final parts = core.split('.');
  final out = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0) return null;
    out.add(n);
  }
  return out.isEmpty ? null : out;
}

/// 자릿수가 달라도(`0.4` vs `0.4.6`) 없는 자리는 0으로 보고 비교한다.
int _compare(List<int> a, List<int> b) {
  final len = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x < y ? -1 : 1;
  }
  return 0;
}
