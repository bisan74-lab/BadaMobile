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
  }) async {
    final r = results[calls++];
    if (r is Exception) throw r;
    return r as MarineForecast;
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
      expect(second.current.windSpeedMs, 5);
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
