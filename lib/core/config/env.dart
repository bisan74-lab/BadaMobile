/// 빌드 시 주입되는 환경 값.
///
/// 예: flutter run --dart-define=DATA_GO_KR_API_KEY=발급받은키
/// API 키는 절대 저장소에 커밋하지 않는다.
class Env {
  Env._();

  /// 공공데이터포털(data.go.kr) 일반 인증키.
  ///
  /// 계정 공통 키이므로 활용신청이 승인된 모든 API에 사용된다:
  /// - 바다낚시지수 조회 (승인됨)
  /// - 조석예보 조회 (추가 활용신청 필요)
  static const dataGoKrApiKey = String.fromEnvironment('DATA_GO_KR_API_KEY');

  /// (구) KHOA 바다누리 직접 발급 키. data.go.kr 키와 별도로 쓸 경우에만 주입.
  static const khoaApiKey = String.fromEnvironment(
    'KHOA_API_KEY',
    defaultValue: '',
  );

  /// 실제 API 대신 목 데이터를 사용할지 여부. 키가 없으면 자동으로 목 사용.
  static bool get useMockData => dataGoKrApiKey.isEmpty && khoaApiKey.isEmpty;
}
