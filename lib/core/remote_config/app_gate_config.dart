/// 강제 업데이트 게이트 설정. `remote_config/app_gate.json`에서 받아온다.
class AppGateConfig {
  const AppGateConfig({
    required this.forceUpgrade,
    required this.message,
    required this.storeUrl,
  });

  /// true면 앱 실행을 막고 업데이트 안내 화면만 보여준다.
  final bool forceUpgrade;

  /// 안내 화면에 보여줄 메시지.
  final String message;

  /// "업데이트" 버튼을 누르면 열리는 스토어 링크.
  final String storeUrl;

  /// 설정을 못 받아왔을 때(오프라인·서버 오류 등) 쓰는 기본값 — 항상 앱을
  /// 정상 실행시킨다. 강제 업데이트 확인 실패를 이유로 사용자를 막지 않는다.
  static const disabled = AppGateConfig(
    forceUpgrade: false,
    message: '',
    storeUrl: '',
  );

  factory AppGateConfig.fromJson(Map<String, dynamic> json) => AppGateConfig(
    forceUpgrade: json['forceUpgrade'] as bool? ?? false,
    message: json['message'] as String? ?? '새 버전으로 업데이트해 주세요.',
    storeUrl: json['storeUrl'] as String? ?? '',
  );
}
