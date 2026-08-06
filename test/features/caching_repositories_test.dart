import 'package:bada_mobile/core/errors/data_errors.dart';
import 'package:bada_mobile/core/storage/cache_store.dart';
import 'package:bada_mobile/features/fishing/data/models/fishing_index.dart';
import 'package:bada_mobile/features/fishing/data/repositories/caching_fishing_repository.dart';
import 'package:bada_mobile/features/fishing/data/repositories/fishing_repository.dart';
import 'package:bada_mobile/features/locations/data/models/sea_location.dart';
import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:bada_mobile/features/tide/data/models/tide_data.dart';
import 'package:bada_mobile/features/tide/data/repositories/caching_tide_repository.dart';
import 'package:bada_mobile/features/tide/data/repositories/tide_repository.dart';
import 'package:bada_mobile/features/weather/data/models/marine_weather.dart';
import 'package:bada_mobile/features/weather/data/repositories/caching_marine_weather_repository.dart';
import 'package:bada_mobile/features/weather/data/repositories/marine_weather_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 호출마다 정해진 결과(값 또는 예외)를 순서대로 돌려주는 가짜 조석 리포지토리.
class _FlakyTideRepository implements TideRepository {
  _FlakyTideRepository(this.results);
  final List<Object> results;
  int calls = 0;

  @override
  Future<TideDay> fetchTideDay(SeaLocation location, DateTime date) async {
    final r = results[calls++];
    if (r is Exception) throw r;
    return r as TideDay;
  }
}

class _FlakyWeatherRepository implements MarineWeatherRepository {
  _FlakyWeatherRepository(this.results);
  final List<Object> results;
  int calls = 0;

  @override
  Future<MarineForecast> fetchForecast(
    SeaLocation location, {
    int hours = defaultForecastHours,
    int pastDays = 0,
  }) async {
    final r = results[calls++];
    if (r is Exception) throw r;
    return r as MarineForecast;
  }
}

/// 항상 [forecast]를 주되 호출 수를 세고, [delay]만큼 늦게 답하는 리포지토리.
/// 캐시가 네트워크를 실제로 건너뛰는지, 동시 요청이 합쳐지는지 보기 위한 것.
class _CountingWeatherRepository implements MarineWeatherRepository {
  _CountingWeatherRepository(this.forecast, {this.delay = Duration.zero});
  final MarineForecast forecast;
  final Duration delay;
  int calls = 0;

  @override
  Future<MarineForecast> fetchForecast(
    SeaLocation location, {
    int hours = defaultForecastHours,
    int pastDays = 0,
  }) async {
    calls++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return forecast;
  }
}

class _FlakyFishingRepository implements FishingRepository {
  _FlakyFishingRepository(this.results);
  final List<Object> results;
  int calls = 0;

  @override
  Future<FishingForecast> fetchForecast(SeaLocation location) async {
    final r = results[calls++];
    if (r is Exception) throw r;
    return r as FishingForecast;
  }
}

Future<CacheStore> newCache() async {
  SharedPreferences.setMockInitialValues({});
  return CacheStore(await SharedPreferences.getInstance());
}

void main() {
  final loc = sampleLocations.first;
  final date = DateTime(2026, 8, 1);

  group('CachingTideRepository', () {
    final sample = TideDay(
      date: date,
      locationId: loc.id,
      extremes: [
        TideExtreme(
          time: date.add(const Duration(hours: 6)),
          heightCm: 500,
          isHigh: true,
        ),
      ],
      hourlyHeightsCm: List.filled(25, 300.0),
    );

    test('성공 응답을 그대로 반환하고 캐시에 저장한다', () async {
      final cache = await newCache();
      final repo = CachingTideRepository(
        inner: _FlakyTideRepository([sample]),
        cache: cache,
      );
      final result = await repo.fetchTideDay(loc, date);
      expect(result.extremes.single.heightCm, 500);
      expect(cache.readJson('tide_${loc.id}_20260801'), isNotNull);
    });

    test('실패 시 이전에 캐시된 결과로 폴백한다', () async {
      final cache = await newCache();
      final repo = CachingTideRepository(
        inner: _FlakyTideRepository([sample, Exception('network down')]),
        cache: cache,
      );
      await repo.fetchTideDay(loc, date); // 1차 성공 → 캐시 저장
      final second = await repo.fetchTideDay(loc, date); // 2차 실패 → 캐시 사용
      expect(second.extremes.single.heightCm, 500);
    });

    test('캐시도 없이 실패하면 예외를 던진다', () async {
      final cache = await newCache();
      final repo = CachingTideRepository(
        inner: _FlakyTideRepository([Exception('no network')]),
        cache: cache,
      );
      expect(() => repo.fetchTideDay(loc, date), throwsException);
    });

    test('범위 초과(DataRangeException)는 캐시로 가리지 않고 그대로 던진다', () async {
      final cache = await newCache();
      final repo = CachingTideRepository(
        inner: _FlakyTideRepository([
          sample,
          const DataRangeException('범위 초과'),
        ]),
        cache: cache,
      );
      await repo.fetchTideDay(loc, date); // 캐시 생김
      expect(
        () => repo.fetchTideDay(loc, date),
        throwsA(isA<DataRangeException>()),
      );
    });
  });

  group('CachingMarineWeatherRepository', () {
    final sample = MarineForecast(
      locationId: loc.id,
      hourly: [
        HourlyMarine(
          time: DateTime(2026, 8, 1, 9),
          windSpeedMs: 5,
          windGustMs: 7,
          windDirectionDeg: 200,
          waveHeightM: 1.2,
          wavePeriodS: 6,
          waveDirectionDeg: 210,
          waterTempC: 22,
          airTempC: 27,
        ),
      ],
    );

    test('실패 시 캐시된 예보로 폴백한다', () async {
      final cache = await newCache();
      final repo = CachingMarineWeatherRepository(
        inner: _FlakyWeatherRepository([sample, Exception('offline')]),
        cache: cache,
      );
      await repo.fetchForecast(loc);
      final second = await repo.fetchForecast(loc);
      // 예보 시각이 한참 지난 캐시라 "신선한 캐시" 경로로는 안 쓰이고,
      // 조회가 깨졌을 때의 폴백으로만 쓰인다.
      expect(second.current.windSpeedMs, 5);
    });

    /// 예보 시간축을 [from]부터 [count]시간 만든다.
    MarineForecast forecastFrom(DateTime from, {int count = 24}) =>
        MarineForecast(
          locationId: loc.id,
          hourly: [
            for (var i = 0; i < count; i++)
              HourlyMarine(
                time: from.add(Duration(hours: i)),
                windSpeedMs: 5,
                windGustMs: 7,
                windDirectionDeg: 200,
                waveHeightM: 1.2,
                wavePeriodS: 6,
                waveDirectionDeg: 210,
                waterTempC: 22,
                airTempC: 27,
              ),
          ],
        );

    test('신선한 캐시가 있으면 네트워크를 아예 타지 않는다', () async {
      var now = DateTime(2026, 8, 1, 9);
      final inner = _CountingWeatherRepository(forecastFrom(now));
      final repo = CachingMarineWeatherRepository(
        inner: inner,
        cache: await newCache(),
        now: () => now,
      );

      await repo.fetchForecast(loc);
      expect(inner.calls, 1);

      now = now.add(const Duration(minutes: 20)); // freshFor(30분) 안
      final second = await repo.fetchForecast(loc);
      expect(inner.calls, 1, reason: '30분 안이면 다시 물어보지 않는다');
      expect(second.current.windSpeedMs, 5);
    });

    test('캐시가 오래되면 다시 조회한다', () async {
      var now = DateTime(2026, 8, 1, 9);
      final inner = _CountingWeatherRepository(forecastFrom(now));
      final repo = CachingMarineWeatherRepository(
        inner: inner,
        cache: await newCache(),
        now: () => now,
      );

      await repo.fetchForecast(loc);
      now = now.add(const Duration(minutes: 31));
      await repo.fetchForecast(loc);
      expect(inner.calls, 2);
    });

    test('캐시로 답할 때 이미 지난 시간은 떼어 낸다', () async {
      var now = DateTime(2026, 8, 1, 9);
      final repo = CachingMarineWeatherRepository(
        inner: _CountingWeatherRepository(forecastFrom(now)),
        cache: await newCache(),
        // 실제 값(30분)으로는 시간 경계를 넘기 어려워 넉넉히 잡는다.
        freshFor: const Duration(hours: 6),
        now: () => now,
      );

      final first = await repo.fetchForecast(loc);
      expect(first.current.time, DateTime(2026, 8, 1, 9));

      // 두 시간 뒤에 다시 보면 "현재"가 11시여야 한다. 안 떼어 내면 9시가
      // 현재로 표시된다.
      now = now.add(const Duration(hours: 2));
      final later = await repo.fetchForecast(loc);
      expect(later.current.time, DateTime(2026, 8, 1, 11));
    });

    test('과거를 일부러 포함해 받는 요청(pastDays)은 캐시를 안 자른다', () async {
      var now = DateTime(2026, 8, 1, 9);
      // 홈 화면처럼 과거 하루치를 포함해 받은 예보.
      final inner = _CountingWeatherRepository(
        forecastFrom(now.subtract(const Duration(hours: 24)), count: 48),
      );
      final repo = CachingMarineWeatherRepository(
        inner: inner,
        cache: await newCache(),
        now: () => now,
      );

      await repo.fetchForecast(loc, pastDays: 1);
      now = now.add(const Duration(minutes: 10));
      final second = await repo.fetchForecast(loc, pastDays: 1);
      expect(inner.calls, 1);
      expect(second.hourly.first.time, DateTime(2026, 7, 31, 9));
    });

    test('동시에 같은 지점을 물어도 요청은 한 번만 나간다', () async {
      final now = DateTime(2026, 8, 1, 9);
      final inner = _CountingWeatherRepository(
        forecastFrom(now),
        delay: const Duration(milliseconds: 20),
      );
      final repo = CachingMarineWeatherRepository(
        inner: inner,
        cache: await newCache(),
        now: () => now,
      );

      final results = await Future.wait([
        repo.fetchForecast(loc),
        repo.fetchForecast(loc),
        repo.fetchForecast(loc),
      ]);
      expect(inner.calls, 1);
      expect(results.every((r) => r.current.windSpeedMs == 5), isTrue);
    });

    test('받아 온 시각을 모르는 옛 형식 캐시는 신선하다고 보지 않는다', () async {
      final now = DateTime(2026, 8, 1, 9);
      final cache = await newCache();
      // 봉투(fetchedAt) 없이 예보만 저장하던 시절의 캐시.
      await cache.writeJson(
        'weather_${loc.id}_${defaultForecastHours}_0',
        forecastFrom(now).toJson(),
      );
      final inner = _CountingWeatherRepository(forecastFrom(now));
      final repo = CachingMarineWeatherRepository(
        inner: inner,
        cache: cache,
        now: () => now,
      );

      await repo.fetchForecast(loc);
      expect(inner.calls, 1, reason: '나이를 모르면 물어봐야 한다');
    });
  });

  group('CachingFishingRepository', () {
    final sample = FishingForecast(
      locationId: loc.id,
      indices: [
        FishingIndex(
          date: DateTime.now(),
          timeSlot: '오전',
          grade: FishingGrade.good,
          species: '감성돔',
        ),
      ],
    );

    test('실패 시 캐시된 지수로 폴백한다', () async {
      final cache = await newCache();
      final repo = CachingFishingRepository(
        inner: _FlakyFishingRepository([sample, Exception('offline')]),
        cache: cache,
      );
      await repo.fetchForecast(loc);
      final second = await repo.fetchForecast(loc);
      expect(second.indices.single.grade, FishingGrade.good);
    });
  });
}
