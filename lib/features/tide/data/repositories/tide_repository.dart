import '../../../locations/data/models/sea_location.dart';
import '../models/tide_data.dart';

/// 조석 데이터 소스 추상화.
///
/// 현재 구현: [MockTideRepository] (합성 데이터)
/// 계획: KhoaTideRepository — KHOA 바다누리 조석예보 API 연동
abstract class TideRepository {
  Future<TideDay> fetchTideDay(SeaLocation location, DateTime date);
}
