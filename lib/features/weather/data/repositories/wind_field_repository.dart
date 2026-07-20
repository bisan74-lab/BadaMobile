import '../models/wind_field.dart';

/// 바람장(격자) 데이터 소스 추상화.
///
/// 구현: [OpenMeteoWindFieldRepository] (실데이터), [MockWindFieldRepository] (합성)
abstract class WindFieldRepository {
  /// 현재 시점 바람장 스냅샷 하나.
  Future<WindField> fetchField();

  /// 지금부터 [hours]시간(1시간 간격) 바람장 시계열 — 시간 스크러버용.
  Future<WindFieldSeries> fetchSeries({int hours = 48});

  /// 특정 지점(정확한 위경도)의 시간별 바람 — 커서 지점 표시용.
  /// 격자 보간은 국지 바람이 뭉개져 약하게 나오므로, 화면에 숫자로 보여주는
  /// 지점값은 이걸 쓴다(윈디의 지점 표시도 원해상도 지점값이다).
  Future<List<PointWind>> fetchPointSeries(
    double lat,
    double lon, {
    int days = 16,
  });
}
