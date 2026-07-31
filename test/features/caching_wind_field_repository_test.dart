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
    expect(inner.calls, 1); // freshFor(기본 15분) 안이라 재요청 없음
  });

  test('3시간 간격 시계열(서버 파일)의 시각이 캐시 왕복에도 보존된다', () async {
    // 회귀 테스트: 예전엔 캐시 write에 stepHours를 안 담아, read 시 무조건
    // 1시간 간격으로 복원해(Duration(hours: h)) 3시간 간격 15일치가 5일로
    // 압축되던 버그가 있었다(지도 스크러버가 실제보다 훨씬 일찍 끝나 보임).
    const latSteps = OpenMeteoWindFieldRepository.latSteps;
    const lonSteps = OpenMeteoWindFieldRepository.lonSteps;
    const pts = latSteps * lonSteps;
    final threeHourly = WindFieldSeries(
      hourly: [
        for (var h = 0; h < 4; h++)
          WindField(
            time: DateTime(2026, 7, 22).add(Duration(hours: h * 3)),
            minLat: 18,
            maxLat: 57,
            minLon: 108,
            maxLon: 148,
            latSteps: latSteps,
            lonSteps: lonSteps,
            u: [for (var k = 0; k < pts; k++) 1.0],
            v: [for (var k = 0; k < pts; k++) 0.0],
          ),
      ],
    );
    final cache = await freshCache();
    final inner = _FakeInner(threeHourly);
    final repo = CachingWindFieldRepository(
      inner: inner,
      cache: cache,
      freshFor: const Duration(seconds: -1), // 항상 실요청 → 캐시 write
    );
    await repo.fetchSeries(hours: 12);
    inner.series = null; // 다음 호출은 캐시 폴백을 타게 한다.
    final fromCache = await repo.fetchSeries(hours: 12);

    expect(fromCache.length, 4);
    // 3시간 간격이 그대로 복원돼야 한다(1시간 간격으로 잘못 복원되면 실패).
    expect(
      fromCache.hourly.last.time.difference(fromCache.hourly.first.time),
      const Duration(hours: 9),
    );
  });

  test('비균일 시간축(앞 1시간·뒤 3시간)도 캐시 왕복에 그대로 보존된다', () async {
    // 서버 파일이 앞 48시간을 1시간 간격으로 담게 되면서 시간축이 비균일해졌다.
    // stepHours 하나로 복원하면 뒷구간 시각이 어긋난다.
    const offsets = [0, 1, 2, 3, 6, 9];
    const latSteps = OpenMeteoWindFieldRepository.latSteps;
    const lonSteps = OpenMeteoWindFieldRepository.lonSteps;
    const pts = latSteps * lonSteps;
    final mixed = WindFieldSeries(
      hourly: [
        for (final h in offsets)
          WindField(
            time: DateTime(2026, 7, 22).add(Duration(hours: h)),
            minLat: 18,
            maxLat: 57,
            minLon: 108,
            maxLon: 148,
            latSteps: latSteps,
            lonSteps: lonSteps,
            u: [for (var k = 0; k < pts; k++) 1.0],
            v: [for (var k = 0; k < pts; k++) 0.0],
          ),
      ],
    );
    final cache = await freshCache();
    final inner = _FakeInner(mixed);
    final repo = CachingWindFieldRepository(
      inner: inner,
      cache: cache,
      freshFor: const Duration(seconds: -1),
    );
    await repo.fetchSeries(hours: 12);
    inner.series = null;
    final fromCache = await repo.fetchSeries(hours: 12);

    expect(fromCache.length, offsets.length);
    final first = fromCache.hourly.first.time;
    for (var i = 0; i < offsets.length; i++) {
      expect(
        fromCache.hourly[i].time.difference(first).inHours,
        offsets[i],
        reason: '스텝 $i',
      );
    }
  });

  test('캐시도 없이 실패하면 예외를 던진다(상위 합성 폴백으로 넘어감)', () async {
    final cache = await freshCache();
    final inner = _FakeInner(null);
    final repo = CachingWindFieldRepository(inner: inner, cache: cache);

    expect(() => repo.fetchSeries(hours: 3), throwsException);
  });
}
