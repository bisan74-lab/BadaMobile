import '../../../locations/data/models/sea_location.dart';
import '../models/marine_weather.dart';

/// 해양 기상 예보 기본 제공 시간: 16일 (윈디 수준의 2주+ 예보 요구 충족).
const int defaultForecastHours = 16 * 24;

/// 해양 기상 데이터 소스 추상화.
///
/// 구현:
/// - [OpenMeteoMarineRepository] — Open-Meteo Marine/Forecast API (실데이터, 16일)
/// - [MockMarineWeatherRepository] — 합성 데이터 (오프라인/테스트)
/// - [FallbackMarineWeatherRepository] — 실데이터 실패 시 목으로 폴백
abstract class MarineWeatherRepository {
  /// [hours]시간 분량의 시간별 예보를 반환한다. [pastDays]를 주면 그만큼
  /// 과거 데이터를 앞에 붙여서 반환한다(홈 화면의 과거 2주 이동용, 기본 0).
  Future<MarineForecast> fetchForecast(
    SeaLocation location, {
    int hours = defaultForecastHours,
    int pastDays = 0,
  });
}

/// [primary] 실패 시 [fallback]으로 폴백하는 래퍼 (NFR-03).
class FallbackMarineWeatherRepository implements MarineWeatherRepository {
  const FallbackMarineWeatherRepository({
    required this.primary,
    required this.fallback,
  });

  final MarineWeatherRepository primary;
  final MarineWeatherRepository fallback;

  @override
  Future<MarineForecast> fetchForecast(
    SeaLocation location, {
    int hours = defaultForecastHours,
    int pastDays = 0,
  }) async {
    try {
      return await primary.fetchForecast(
        location,
        hours: hours,
        pastDays: pastDays,
      );
    } catch (_) {
      return fallback.fetchForecast(location, hours: hours, pastDays: pastDays);
    }
  }
}
