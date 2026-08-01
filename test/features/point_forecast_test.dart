import 'dart:convert';
import 'dart:io' show gzip;

import 'package:bada_mobile/core/storage/cache_store.dart';
import 'package:bada_mobile/features/locations/data/models/sea_location.dart';
import 'package:bada_mobile/features/weather/data/models/marine_weather.dart';
import 'package:bada_mobile/features/weather/data/repositories/github_point_forecast_repository.dart';
import 'package:bada_mobile/features/weather/data/repositories/marine_weather_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _busan = SeaLocation(
  id: 'busan',
  name: '부산',
  region: '남해',
  latitude: 35.1,
  longitude: 129.05,
);
const _unknown = SeaLocation(
  id: 'made_up',
  name: '검색으로 추가한 곳',
  region: '남해',
  latitude: 34.0,
  longitude: 128.0,
);

/// `tool/fetch_points.py`가 만드는 것과 같은 구조.
/// 시각은 테스트 실행 시각을 기준으로 3시간 간격 8스텝(과거 1 + 미래 7).
String sampleFile({DateTime? generated}) {
  final base = DateTime.now();
  final start = DateTime(
    base.year,
    base.month,
    base.day,
    base.hour,
  ).subtract(const Duration(hours: 3));
  String iso(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-'
      '${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}T'
      '${t.hour.toString().padLeft(2, '0')}:00';

  final times = [
    for (var i = 0; i < 8; i++) iso(start.add(Duration(hours: i * 3))),
  ];
  List<double> ramp(double from, double step) => [
    for (var i = 0; i < times.length; i++) from + step * i,
  ];

  return jsonEncode({
    'fmt': 1,
    'generated':
        '${(generated ?? DateTime.now().toUtc()).toIso8601String().split('.').first}Z',
    'stepHours': 3,
    'vars': ['windMs', 'gustMs', 'dirDeg', 'waveM', 'periodS', 'sstC', 'airC'],
    'times': times,
    'locations': ['busan'],
    'series': [
      [
        ramp(3.0, 0.5), // windMs
        ramp(6.0, 1.0), // gustMs
        ramp(200, 5), // dirDeg
        ramp(0.5, 0.1), // waveM
        ramp(4.0, 0.2), // periodS
        ramp(24.0, 0.1), // sstC
        ramp(28.0, 0.2), // airC
      ],
    ],
  });
}

/// 실패만 하는 폴백(서버 파일 경로가 실제로 쓰였는지 확인용).
class _NeverRepository implements MarineWeatherRepository {
  int calls = 0;
  @override
  Future<MarineForecast> fetchForecast(
    SeaLocation location, {
    int hours = defaultForecastHours,
    int pastDays = 0,
  }) async {
    calls++;
    throw StateError('직접 호출로 내려가면 안 된다');
  }
}

class _StubRepository implements MarineWeatherRepository {
  int calls = 0;
  @override
  Future<MarineForecast> fetchForecast(
    SeaLocation location, {
    int hours = defaultForecastHours,
    int pastDays = 0,
  }) async {
    calls++;
    return MarineForecast(locationId: location.id, hourly: const []);
  }
}

http.Response _json(String body) => http.Response(
  body,
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<CacheStore> _freshCache() async {
  SharedPreferences.setMockInitialValues({});
  return CacheStore(await SharedPreferences.getInstance());
}

void main() {
  setUp(GithubPointForecastRepository.clearMemoryCache);

  group('parsePointForecastFile', () {
    test('변수 순서대로 시간별 값을 되돌린다', () {
      final file = parsePointForecastFile(sampleFile());

      expect(file.times, hasLength(8));
      final busan = file.byLocation['busan']!;
      expect(busan, hasLength(8));
      expect(busan.first.windSpeedMs, closeTo(3.0, 0.001));
      expect(busan.first.windGustMs, closeTo(6.0, 0.001));
      expect(busan.first.windDirectionDeg, closeTo(200, 0.001));
      expect(busan.first.waveHeightM, closeTo(0.5, 0.001));
      expect(busan.first.wavePeriodS, closeTo(4.0, 0.001));
      expect(busan.first.waterTempC, closeTo(24.0, 0.001));
      expect(busan.first.airTempC, closeTo(28.0, 0.001));
      // 돌풍은 낚시정보 카드가 쓰는 값이라 반드시 실려야 한다.
      expect(busan.last.windGustMs, closeTo(13.0, 0.001));
    });

    test('과거를 요청하지 않으면 지난 시각을 잘라 낸다', () {
      final file = parsePointForecastFile(sampleFile());

      final now = file.forecastFor(_busan)!;
      expect(
        now.hourly.first.time.isAfter(
          DateTime.now().subtract(const Duration(hours: 4)),
        ),
        isTrue,
      );

      final withPast = file.forecastFor(_busan, pastDays: 14)!;
      expect(withPast.hourly.length, greaterThanOrEqualTo(now.hourly.length));
    });

    test('파일에 없는 지역은 null (호출자가 직접 호출로 폴백)', () {
      final file = parsePointForecastFile(sampleFile());
      expect(file.forecastFor(_unknown), isNull);
    });
  });

  group('GithubPointForecastRepository', () {
    test('지역을 여러 번 조회해도 파일은 한 번만 받는다', () async {
      final cache = await _freshCache();
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return _json(sampleFile());
      });
      final direct = _NeverRepository();
      final repo = GithubPointForecastRepository(
        direct: direct,
        cache: cache,
        client: client,
        url: 'https://example.test/point_forecast.json.gz',
      );

      for (var i = 0; i < 5; i++) {
        final f = await repo.fetchForecast(_busan, pastDays: 14);
        expect(f.hourly, isNotEmpty);
      }

      // 예전엔 지역마다 Open-Meteo를 5번씩 불러 1~2초가 걸렸다.
      expect(calls, 1);
      expect(direct.calls, 0);
    });

    test('gzip으로 내려와도 푼다', () async {
      final cache = await _freshCache();
      final client = MockClient(
        (_) async =>
            http.Response.bytes(gzip.encode(utf8.encode(sampleFile())), 200),
      );
      final repo = GithubPointForecastRepository(
        direct: _NeverRepository(),
        cache: cache,
        client: client,
        url: 'https://example.test/point_forecast.json.gz',
      );

      final f = await repo.fetchForecast(_busan);
      expect(f.hourly.first.windGustMs, greaterThan(0));
    });

    test('파일에 없는 지역은 직접 호출로 넘긴다', () async {
      final cache = await _freshCache();
      final direct = _StubRepository();
      final repo = GithubPointForecastRepository(
        direct: direct,
        cache: cache,
        client: MockClient((_) async => _json(sampleFile())),
        url: 'https://example.test/point_forecast.json.gz',
      );

      await repo.fetchForecast(_unknown);
      expect(direct.calls, 1);
    });

    test('파일을 못 받으면 직접 호출로 폴백한다', () async {
      final cache = await _freshCache();
      final direct = _StubRepository();
      final repo = GithubPointForecastRepository(
        direct: direct,
        cache: cache,
        client: MockClient((_) async => http.Response('nope', 404)),
        url: 'https://example.test/point_forecast.json.gz',
      );

      await repo.fetchForecast(_busan);
      expect(direct.calls, 1);
    });

    test('오프라인이면 마지막으로 받아 둔 파일을 쓴다', () async {
      final cache = await _freshCache();
      const url = 'https://example.test/point_forecast.json.gz';

      await GithubPointForecastRepository(
        direct: _NeverRepository(),
        cache: cache,
        client: MockClient((_) async => _json(sampleFile())),
        url: url,
      ).fetchForecast(_busan);

      // 저장은 일부러 await하지 않는다(화면을 먼저 그리려고).
      for (
        var i = 0;
        i < 200 && cache.readString('point_forecast') == null;
        i++
      ) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(cache.readString('point_forecast'), isNotNull);

      GithubPointForecastRepository.clearMemoryCache();
      final f = await GithubPointForecastRepository(
        direct: _NeverRepository(),
        cache: cache,
        client: MockClient((_) async => throw http.ClientException('오프라인')),
        url: url,
      ).fetchForecast(_busan);

      expect(f.hourly, isNotEmpty);
    });
  });
}
