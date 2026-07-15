/// 빌드 시 주입되는 환경 값.
///
/// 예: flutter run --dart-define=KHOA_API_KEY=발급받은키
/// API 키는 절대 저장소에 커밋하지 않는다.
class Env {
  Env._();

  /// KHOA 바다누리 해양정보서비스 Open API 키 (조석 예보용, 추후 연동).
  static const khoaApiKey = String.fromEnvironment('KHOA_API_KEY');

  /// 실제 API 대신 목 데이터를 사용할지 여부. 키가 없으면 자동으로 목 사용.
  static bool get useMockData => khoaApiKey.isEmpty;
}
