import '../../../../core/storage/cache_store.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/fishing_index.dart';
import 'fishing_repository.dart';

/// [inner]로 조회하되 성공 시 로컬에 캐시하고, 실패(오프라인 등) 시 캐시로
/// 폴백하는 래퍼 (FR-11). 캐시에도 없으면 원래 예외를 다시 던진다.
class CachingFishingRepository implements FishingRepository {
  CachingFishingRepository({required this.inner, required this.cache});

  final FishingRepository inner;
  final CacheStore cache;

  static String _key(SeaLocation location) {
    final now = DateTime.now();
    final ymd =
        '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return 'fishing_${location.id}_$ymd';
  }

  @override
  Future<FishingForecast> fetchForecast(SeaLocation location) async {
    try {
      final result = await inner.fetchForecast(location);
      await cache.writeJson(_key(location), result.toJson());
      return result;
    } catch (_) {
      final cached = cache.readJson(_key(location));
      if (cached != null) return FishingForecast.fromJson(cached);
      rethrow;
    }
  }
}
