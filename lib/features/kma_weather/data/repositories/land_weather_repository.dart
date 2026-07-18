import '../../../locations/data/models/sea_location.dart';
import '../models/land_weather.dart';

/// 육상 날씨 예보 데이터 소스 추상화.
///
/// 구현:
/// - [OpenMeteoLandWeatherRepository] — Open-Meteo Forecast/Air-Quality(실데이터, 16일)
/// - [MockLandWeatherRepository] — 합성 데이터(오프라인/테스트)
abstract class LandWeatherRepository {
  Future<WeatherForecast> fetchForecast(SeaLocation location);

  /// [primary] 실패 시 [fallback]으로 폴백하는 래퍼 (NFR-03).
  factory LandWeatherRepository.withFallback({
    required LandWeatherRepository primary,
    required LandWeatherRepository fallback,
  }) = _FallbackLandWeatherRepository;
}

class _FallbackLandWeatherRepository implements LandWeatherRepository {
  const _FallbackLandWeatherRepository({
    required this.primary,
    required this.fallback,
  });

  final LandWeatherRepository primary;
  final LandWeatherRepository fallback;

  @override
  Future<WeatherForecast> fetchForecast(SeaLocation location) async {
    try {
      return await primary.fetchForecast(location);
    } catch (_) {
      return fallback.fetchForecast(location);
    }
  }
}
