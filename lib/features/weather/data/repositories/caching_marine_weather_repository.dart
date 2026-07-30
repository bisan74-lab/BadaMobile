import 'dart:async';

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

  static String _key(SeaLocation location, int hours, int pastDays) =>
      'weather_${location.id}_${hours}_$pastDays';

  @override
  Future<MarineForecast> fetchForecast(
    SeaLocation location, {
    int hours = defaultForecastHours,
    int pastDays = 0,
  }) async {
    try {
      final result = await inner.fetchForecast(
        location,
        hours: hours,
        pastDays: pastDays,
      );
      final write = cache.writeJson(
        _key(location, hours, pastDays),
        result.toJson(),
      );
      if (location.id.startsWith('pt_')) {
        // 지도를 탭해 만든 즉석 지점(pointSeaLocation, id가 'pt_위도_경도')은
        // 사용자가 같은 111m 반경을 다시 찍을 확률이 낮아 캐시 이득이 거의
        // 없는데, await로 묶여 있으면 예보를 다 받고도 디스크 쓰기가 끝날
        // 때까지 상세 예보 표시가 늦어졌다(사용자 지적: "상세 예보 로딩이
        // 오래 걸린다"). 그래서 이 경우만 쓰기를 기다리지 않는다(실패해도
        // 화면엔 영향 없으므로 조용히 무시). 등록된 지역은 오프라인 폴백
        // 신뢰성이 중요하므로 기존대로 기다린다.
        unawaited(write.catchError((_) {}));
      } else {
        await write;
      }
      return result;
    } catch (_) {
      final cached = cache.readJson(_key(location, hours, pastDays));
      if (cached != null) return MarineForecast.fromJson(cached);
      rethrow;
    }
  }
}
