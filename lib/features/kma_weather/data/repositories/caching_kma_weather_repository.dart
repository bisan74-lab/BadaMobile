import '../../../../core/storage/cache_store.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/kma_forecast.dart';
import 'kma_weather_repository.dart';

/// [inner]로 조회하되 성공 시 로컬에 캐시하고, 실패(오프라인 등) 시 캐시로
/// 폴백하는 래퍼 (FR-11). 캐시에도 없으면 원래 예외를 다시 던진다.
class CachingKmaWeatherRepository implements KmaWeatherRepository {
  CachingKmaWeatherRepository({required this.inner, required this.cache});

  final KmaWeatherRepository inner;
  final CacheStore cache;

  static String _key(SeaLocation location) => 'kma_weather_${location.id}';

  @override
  Future<KmaForecast> fetchForecast(SeaLocation location) async {
    try {
      final result = await inner.fetchForecast(location);
      await cache.writeJson(_key(location), result.toJson());
      return result;
    } catch (_) {
      final cached = cache.readJson(_key(location));
      if (cached != null) return KmaForecast.fromJson(cached);
      rethrow;
    }
  }
}
