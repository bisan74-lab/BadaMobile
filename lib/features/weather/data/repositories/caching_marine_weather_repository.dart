import '../../../../core/storage/cache_store.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/marine_weather.dart';
import 'marine_weather_repository.dart';

/// [inner]로 조회하되 성공 시 로컬에 캐시하고, 실패(오프라인 등) 시 캐시로
/// 폴백하는 래퍼 (FR-11). 캐시에도 없으면 원래 예외를 다시 던진다.
class CachingMarineWeatherRepository implements MarineWeatherRepository {
  CachingMarineWeatherRepository({required this.inner, required this.cache});

  final MarineWeatherRepository inner;
  final CacheStore cache;

  static String _key(SeaLocation location, int hours) =>
      'weather_${location.id}_$hours';

  @override
  Future<MarineForecast> fetchForecast(
    SeaLocation location, {
    int hours = defaultForecastHours,
  }) async {
    try {
      final result = await inner.fetchForecast(location, hours: hours);
      await cache.writeJson(_key(location, hours), result.toJson());
      return result;
    } catch (_) {
      final cached = cache.readJson(_key(location, hours));
      if (cached != null) return MarineForecast.fromJson(cached);
      rethrow;
    }
  }
}
