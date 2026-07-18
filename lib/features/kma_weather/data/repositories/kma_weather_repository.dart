import '../../../locations/data/models/sea_location.dart';
import '../models/kma_forecast.dart';

/// 기상청(육상) 단기예보 데이터 소스 추상화.
///
/// 구현:
/// - [MockKmaWeatherRepository] — 합성 데이터
/// - [DataGoKrKmaRepository] — 공공데이터포털 기상청 단기예보 조회서비스
abstract class KmaWeatherRepository {
  Future<KmaForecast> fetchForecast(SeaLocation location);

  /// [primary] 실패 시 [fallback]으로 폴백하는 래퍼 (NFR-03).
  factory KmaWeatherRepository.withFallback({
    required KmaWeatherRepository primary,
    required KmaWeatherRepository fallback,
  }) = _FallbackKmaWeatherRepository;
}

class _FallbackKmaWeatherRepository implements KmaWeatherRepository {
  const _FallbackKmaWeatherRepository({
    required this.primary,
    required this.fallback,
  });

  final KmaWeatherRepository primary;
  final KmaWeatherRepository fallback;

  @override
  Future<KmaForecast> fetchForecast(SeaLocation location) async {
    try {
      return await primary.fetchForecast(location);
    } catch (_) {
      return fallback.fetchForecast(location);
    }
  }
}
