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

  /// [primary] 실패 시 [fallback]으로 폴백하는 래퍼 (NFR-03).
  factory FishingRepository.withFallback({
    required FishingRepository primary,
    required FishingRepository fallback,
  }) = _FallbackFishingRepository;
}

class _FallbackFishingRepository implements FishingRepository {
  const _FallbackFishingRepository({
    required this.primary,
    required this.fallback,
  });

  final FishingRepository primary;
  final FishingRepository fallback;

  @override
  Future<FishingForecast> fetchForecast(SeaLocation location) async {
    try {
      return await primary.fetchForecast(location);
    } catch (_) {
      return fallback.fetchForecast(location);
    }
  }
}
