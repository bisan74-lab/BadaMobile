import 'dart:async';

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
      // 저장이 끝나기를 기다리지 않는다 — 결과는 이미 손에 있는데 디스크
      // 쓰기까지 기다리면 그만큼 화면에 늦게 뜬다. 실패해도 다음 조회에서
      // 다시 쓰므로 조용히 넘긴다.
      unawaited(
        cache.writeJson(_key(location), result.toJson()).catchError((_) {}),
      );
      return result;
    } catch (_) {
      final cached = cache.readJson(_key(location));
      if (cached != null) return FishingForecast.fromJson(cached);
      rethrow;
    }
  }
}
