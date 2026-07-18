import '../../../../core/storage/cache_store.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/land_weather.dart';
import 'land_weather_repository.dart';

/// [inner]로 조회하되 성공 시 로컬에 캐시하고, 실패(오프라인 등) 시 캐시로
/// 폴백하는 래퍼 (FR-11). 캐시에도 없으면 원래 예외를 다시 던진다.
class CachingLandWeatherRepository implements LandWeatherRepository {
  CachingLandWeatherRepository({required this.inner, required this.cache});

  final LandWeatherRepository inner;
  final CacheStore cache;

  static String _key(SeaLocation location) => 'land_weather_${location.id}';

  @override
  Future<WeatherForecast> fetchForecast(SeaLocation location) async {
    try {
      final result = await inner.fetchForecast(location);
      await cache.writeJson(_key(location), result.toJson());
      return result;
    } catch (_) {
      final cached = cache.readJson(_key(location));
      if (cached != null) return WeatherForecast.fromJson(cached);
      rethrow;
    }
  }
}
