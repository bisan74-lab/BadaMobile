import '../models/wind_field.dart';

/// 바람장(격자) 데이터 소스 추상화.
///
/// 구현: [OpenMeteoWindFieldRepository] (실데이터), [MockWindFieldRepository] (합성)
abstract class WindFieldRepository {
  Future<WindField> fetchField();
}
