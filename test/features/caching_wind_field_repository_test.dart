import 'package:bada_mobile/core/storage/cache_store.dart';
import 'package:bada_mobile/features/weather/data/models/wind_field.dart';
import 'package:bada_mobile/features/weather/data/repositories/caching_wind_field_repository.dart';
import 'package:bada_mobile/features/weather/data/repositories/open_meteo_wind_field_repository.dart';
import 'package:bada_mobile/features/weather/data/repositories/wind_field_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// series를 주면 성공, null이면 실패하는 가짜 실데이터 리포지토리.
class _FakeInner implements WindFieldRepository {
  _FakeInner(this.series);

  WindFieldSeries? series;
  int calls = 0;

  @override
  Future<WindField> fetchField() async => series!.hourly.first;

  @override
  Future<WindFieldSeries> fetchSeries({int hours = 48}) async {
    calls++;
    final s = series;
    if (s == null) throw Exception('network');
    return s;
  }

  @override
  Future<List<PointWind>> fetchPointSeries(
    double lat,
    double lon, {
    int days = 16,
  }) async => const [];
}

/// 캐시 검증 조건(현재 격자 구성)과 같은 크기의 시계열을 만든다.
WindFieldSeries buildSeries() {
  const latSteps = OpenMeteoWindFieldRepository.latSteps;
  const lonSteps = OpenMeteoWindFieldRepository.lonSteps;
  const pts = latSteps * lonSteps;
  return WindFieldSeries(
    hourly: [
      for (var h = 0; h < 3; h++)
        WindField(
          time: DateTime(2026, 7, 21, h),
          minLat: 18,
          maxLat: 57,
          minLon: 108,
          maxLon: 148,
          latSteps: latSteps,
          lonSteps: lonSteps,
          u: [for (var k = 0; k < pts; k++) (k % 40) / 2 - 5 + h],
          v: [for (var k = 0; k < pts; k++) (k % 25) / 5 - 2],
        ),
    ],
  );
}

Future<CacheStore> freshCache() async {
  SharedPreferences.setMockInitialValues({});
  return CacheStore(await SharedPreferences.getInstance());
}

void main() {
  test('성공 시 캐시에 저장되고, 이후 실패하면 캐시로 폴백한다(값 왕복 보존)', () async {
    final cache = await freshCache();
    final inner = _FakeInner(buildSeries());
    // freshFor를 음수로 두어 항상 실요청을 시도하게 한다(폴백 경로 검증용).
    final repo = CachingWindFieldRepository(
      inner: inner,
      cache: cache,
      freshFor: const Duration(seconds: -1),
    );

    final first = await repo.fetchSeries(hours: 3);
    expect(inner.calls, 1);

    inner.series = null; // 이후 네트워크 실패
    final fallback = await repo.fetchSeries(hours: 3);
    expect(inner.calls, 2); // 실요청 시도는 했고
    expect(fallback.length, first.length);
    for (var h = 0; h < first.length; h++) {
      expect(fallback.hourly[h].time, first.hourly[h].time);
      for (var k = 0; k < first.hourly[h].u.length; k += 97) {
        // int16(cm/s) 양자화라 0.01 이내로 보존된다.
        expect(fallback.hourly[h].u[k], closeTo(first.hourly[h].u[k], 0.011));
        expect(fallback.hourly[h].v[k], closeTo(first.hourly[h].v[k], 0.011));
      }
    }
  });

  test('신선한 캐시는 네트워크 요청 없이 재사용한다', () async {
    final cache = await freshCache();
    final inner = _FakeInner(buildSeries());
    final repo = CachingWindFieldRepository(inner: inner, cache: cache);

    await repo.fetchSeries(hours: 3);
    expect(inner.calls, 1);
    await repo.fetchSeries(hours: 3);
    expect(inner.calls, 1); // freshFor(기본 3시간) 안이라 재요청 없음
  });

  test('캐시도 없이 실패하면 예외를 던진다(상위 합성 폴백으로 넘어감)', () async {
    final cache = await freshCache();
    final inner = _FakeInner(null);
    final repo = CachingWindFieldRepository(inner: inner, cache: cache);

    expect(() => repo.fetchSeries(hours: 3), throwsException);
  });
}
