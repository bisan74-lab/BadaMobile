import '../../../../core/errors/data_errors.dart';
import '../../../../core/storage/cache_store.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/tide_data.dart';
import 'tide_repository.dart';

/// [inner]로 조회하되 성공 시 로컬에 캐시하고, 실패(오프라인 등) 시 캐시로
/// 폴백하는 래퍼 (FR-11). 캐시에도 없으면 원래 예외를 다시 던진다 — 그러면
/// [TideRepository.withFallback]의 바깥 래퍼가 합성 데이터로 이어받는다.
class CachingTideRepository implements TideRepository {
  CachingTideRepository({required this.inner, required this.cache});

  final TideRepository inner;
  final CacheStore cache;

  static String _key(SeaLocation location, DateTime date) =>
      'tide_${location.id}_${date.year}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';

  @override
  Future<TideDay> fetchTideDay(SeaLocation location, DateTime date) async {
    try {
      final result = await inner.fetchTideDay(location, date);
      await cache.writeJson(_key(location, date), result.toJson());
      return result;
    } on DataRangeException {
      rethrow; // 범위 초과는 오프라인 문제가 아니므로 캐시로 가리지 않는다.
    } catch (_) {
      final cached = cache.readJson(_key(location, date));
      if (cached != null) return TideDay.fromJson(cached);
      rethrow;
    }
  }
}
