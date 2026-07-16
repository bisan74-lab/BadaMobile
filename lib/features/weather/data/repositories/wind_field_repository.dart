import '../models/wind_field.dart';

/// 바람장(격자) 데이터 소스 추상화.
///
/// 구현: [OpenMeteoWindFieldRepository] (실데이터), [MockWindFieldRepository] (합성)
abstract class WindFieldRepository {
  /// 현재 시점 바람장 스냅샷 하나.
  Future<WindField> fetchField();

  /// 지금부터 [hours]시간(1시간 간격) 바람장 시계열 — 시간 스크러버용.
  Future<WindFieldSeries> fetchSeries({int hours = 48});
}
