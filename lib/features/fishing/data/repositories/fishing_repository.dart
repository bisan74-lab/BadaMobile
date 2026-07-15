import '../../../locations/data/models/sea_location.dart';
import '../models/fishing_index.dart';

/// 바다낚시지수 데이터 소스 추상화.
///
/// 구현:
/// - [MockFishingRepository] — 합성 데이터
/// - [DataGoKrFishingRepository] — 공공데이터포털 바다낚시지수 조회 API
///   (승인 완료, 응답 필드 매핑은 실제 샘플 응답 확인 후 확정)
abstract class FishingRepository {
  Future<FishingForecast> fetchForecast(SeaLocation location);
}
