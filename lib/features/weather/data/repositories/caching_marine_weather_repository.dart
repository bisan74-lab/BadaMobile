import 'dart:async';

import '../../../../core/storage/cache_store.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/marine_weather.dart';
import 'marine_weather_repository.dart';

/// 캐시가 이 시간 안에 받아 온 것이면 **네트워크를 아예 타지 않는다.**
///
/// Open-Meteo가 물어보는 모델(GFS·WAM)은 몇 시간마다 한 번 갱신되므로 30분
/// 안에 다시 물어봐야 같은 값이 온다. 지도에서 지점을 옮겨 다니거나 앱을
/// 다시 켰을 때 왕복 지연(한국에서 300~800ms × 5건)을 통째로 없앤다.
const Duration marineForecastFreshFor = Duration(minutes: 30);

/// [inner]로 조회하되 결과를 로컬에 캐시하는 래퍼 (FR-11).
///
/// 캐시를 쓰는 경우가 둘이다.
/// - **신선하면 먼저 쓴다**: [freshFor] 안에 받아 온 캐시가 있으면 네트워크를
///   건너뛰고 그대로 돌려준다(요청 0건).
/// - **실패하면 나중에 쓴다**: 오프라인 등으로 조회가 깨지면 나이와 무관하게
///   캐시로 폴백한다. 캐시에도 없으면 원래 예외를 다시 던진다.
class CachingMarineWeatherRepository implements MarineWeatherRepository {
  CachingMarineWeatherRepository({
    required this.inner,
    required this.cache,
    this.freshFor = marineForecastFreshFor,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final MarineWeatherRepository inner;
  final CacheStore cache;

  /// 이 시간 안에 받아 온 캐시는 네트워크 없이 그대로 쓴다.
  final Duration freshFor;

  /// 테스트에서 시간을 밀어 보기 위한 주입점.
  final DateTime Function() _now;

  /// 디코드까지 끝난 캐시. 같은 지점을 반복해서 볼 때 SharedPreferences 읽기와
  /// `jsonDecode`(16일치면 수십 KB)를 매번 다시 하지 않기 위한 것이다.
  /// 지도를 탭해 만든 즉석 지점이 계속 쌓이므로 오래된 것부터 버린다.
  final _memory = <String, _CachedForecast>{};
  static const _memoryLimit = 12;

  /// 같은 키로 이미 날아가 있는 요청. 두 위젯이 동시에 같은 지점을 물어도
  /// 왕복은 한 번만 돈다.
  final _inFlight = <String, Future<MarineForecast>>{};

  static String _key(SeaLocation location, int hours, int pastDays) =>
      'weather_${location.id}_${hours}_$pastDays';

  @override
  Future<MarineForecast> fetchForecast(
    SeaLocation location, {
    int hours = defaultForecastHours,
    int pastDays = 0,
  }) {
    final key = _key(location, hours, pastDays);

    final fresh = _readCached(key, pastDays: pastDays, mustBeFresh: true);
    if (fresh != null) return Future.value(fresh);

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _fetchAndStore(key, location, hours, pastDays);
    _inFlight[key] = future;
    return future.whenComplete(() => _inFlight.remove(key));
  }

  Future<MarineForecast> _fetchAndStore(
    String key,
    SeaLocation location,
    int hours,
    int pastDays,
  ) async {
    try {
      final result = await inner.fetchForecast(
        location,
        hours: hours,
        pastDays: pastDays,
      );
      _remember(key, _CachedForecast(result, _now()));
      final write = cache.writeJson(key, {
        'fetchedAt': _now().toIso8601String(),
        'forecast': result.toJson(),
      });
      if (location.id.startsWith('pt_')) {
        // 지도를 탭해 만든 즉석 지점(pointSeaLocation, id가 'pt_위도_경도')은
        // 사용자가 같은 111m 반경을 다시 찍을 확률이 낮아 디스크 캐시 이득이
        // 거의 없는데, await로 묶여 있으면 예보를 다 받고도 쓰기가 끝날 때까지
        // 상세 예보 표시가 늦어졌다(사용자 지적: "상세 예보 로딩이 오래
        // 걸린다"). 그래서 이 경우만 쓰기를 기다리지 않는다(실패해도 화면엔
        // 영향 없으므로 조용히 무시). 등록된 지역은 오프라인 폴백 신뢰성이
        // 중요하므로 기존대로 기다린다.
        unawaited(write.catchError((_) {}));
      } else {
        await write;
      }
      return result;
    } catch (_) {
      // 조회 실패 — 이때는 나이를 따지지 않고 있는 것을 쓴다.
      final stale = _readCached(key, pastDays: pastDays, mustBeFresh: false);
      if (stale != null) return stale;
      rethrow;
    }
  }

  /// 메모리 → 디스크 순으로 캐시를 찾는다.
  ///
  /// [mustBeFresh]면 [freshFor] 안에 받아 온 것만 돌려준다. 나이를 알 수 없는
  /// 옛 형식(봉투 없이 예보만 저장하던 시절)의 캐시는 신선하다고 볼 근거가
  /// 없으므로 이 경우 건너뛴다 — 폴백으로는 그대로 쓴다.
  MarineForecast? _readCached(
    String key, {
    required int pastDays,
    required bool mustBeFresh,
  }) {
    var entry = _memory[key];
    if (entry == null) {
      final raw = cache.readJson(key);
      if (raw == null) return null;
      try {
        final body = raw['forecast'];
        if (body is Map<String, dynamic>) {
          entry = _CachedForecast(
            MarineForecast.fromJson(body),
            DateTime.tryParse(raw['fetchedAt'] as String? ?? ''),
          );
        } else {
          entry = _CachedForecast(MarineForecast.fromJson(raw), null);
        }
      } catch (_) {
        return null; // 손상된 캐시는 없는 것으로 취급
      }
      _remember(key, entry);
    }

    // 폴백으로 쓸 때는 나이도 내용도 따지지 않는다. 오프라인이라 이것밖에
    // 없는 상황이라, 지나간 예보라도 없는 것보다는 낫다(FR-11).
    if (!mustBeFresh) return entry.forecast;

    final at = entry.fetchedAt;
    if (at == null || _now().difference(at) > freshFor) return null;
    return _usable(entry.forecast, pastDays: pastDays);
  }

  /// 캐시를 지금 시각 기준으로 다듬는다.
  ///
  /// 미래 예보만 요청한 경우([pastDays] 0) `hourly.first`가 곧 "현재"라서,
  /// 30분 전에 받은 캐시를 그대로 주면 지난 시각이 현재로 표시된다. 그래서
  /// 이번 시간 이전 항목은 떼어 낸다. 과거를 일부러 포함해 받는 홈 화면
  /// (`pastDays > 0`)은 그 과거가 데이터이므로 손대지 않는다.
  MarineForecast? _usable(MarineForecast forecast, {required int pastDays}) {
    if (pastDays > 0) return forecast;
    final now = _now();
    final thisHour = DateTime(now.year, now.month, now.day, now.hour);
    final from = forecast.hourly.indexWhere((h) => !h.time.isBefore(thisHour));
    if (from < 0) return null; // 전부 지나간 예보 — 없는 것으로 친다
    if (from == 0) return forecast;
    return MarineForecast(
      locationId: forecast.locationId,
      hasWaveData: forecast.hasWaveData,
      hourly: forecast.hourly.sublist(from),
    );
  }

  void _remember(String key, _CachedForecast entry) {
    _memory.remove(key); // 다시 넣어 삽입 순서를 최신으로
    _memory[key] = entry;
    while (_memory.length > _memoryLimit) {
      _memory.remove(_memory.keys.first);
    }
  }
}

class _CachedForecast {
  const _CachedForecast(this.forecast, this.fetchedAt);

  final MarineForecast forecast;

  /// 받아 온 시각. 옛 형식 캐시엔 없어서 null일 수 있다.
  final DateTime? fetchedAt;
}
