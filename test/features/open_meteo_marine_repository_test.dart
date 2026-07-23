import 'dart:convert';

import 'package:bada_mobile/features/locations/data/models/sea_location.dart';
import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:bada_mobile/features/weather/data/repositories/open_meteo_marine_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// [hours]시간 분량의 Open-Meteo 형식 hourly 블록을 만든다.
Map<String, dynamic> _hourlyBlock(List<String> keys, int hours) {
  final start = DateTime(2026, 7, 15);
  return {
    'time': List.generate(
      hours,
      (i) => start.add(Duration(hours: i)).toIso8601String().substring(0, 16),
    ),
    for (final k in keys)
      k: List<double?>.generate(hours, (i) => (i % 10) + 1.0),
  };
}

void main() {
  const hours = 16 * 24;

  MockClient buildClient({int marineStatus = 200}) {
    return MockClient((request) async {
      if (request.url.host == 'marine-api.open-meteo.com') {
        expect(request.url.queryParameters['forecast_days'], '16');
        return http.Response(
          jsonEncode({
            'hourly': _hourlyBlock([
              'wave_height',
              'wave_period',
              'wave_direction',
              'sea_surface_temperature',
              'swell_wave_height',
              'swell_wave_period',
            ], hours),
          }),
          marineStatus,
        );
      }
      expect(request.url.host, 'api.open-meteo.com');
      expect(request.url.queryParameters['wind_speed_unit'], 'ms');
      // 바람은 지도 바람장·Windy와 같은 ECMWF IFS로 고정한다(best_match면
      // 연안 지역모델이 선택돼 지속풍이 낮게 나와 표·지도·Windy가 어긋난다).
      expect(request.url.queryParameters['models'], 'ecmwf_ifs025');
      return http.Response(
        jsonEncode({
          'hourly': _hourlyBlock([
            'wind_speed_10m',
            'wind_gusts_10m',
            'wind_direction_10m',
            'temperature_2m',
          ], hours),
        }),
        200,
      );
    });
  }

  test('16일(384시간) 예보를 병합해 반환한다 — 최소 2주 요건 충족', () async {
    final repo = OpenMeteoMarineRepository(client: buildClient());
    final forecast = await repo.fetchForecast(sampleLocations.first);

    expect(forecast.hourly, hasLength(hours));
    expect(forecast.forecastDays, greaterThanOrEqualTo(14));
    final first = forecast.hourly.first;
    expect(first.windSpeedMs, 1.0);
    expect(first.waveHeightM, 1.0);
    expect(first.wavePeriodS, 1.0);
    expect(first.waveDirectionDeg, 1.0);
    expect(first.swellHeightM, 1.0);
    expect(first.swellPeriodS, 1.0);
    // 파력 = 0.49 · H² · T = 0.49 · 1 · 1
    expect(first.wavePowerKw, closeTo(0.49, 1e-9));
  });

  test('marine 응답의 null 값은 직전 값으로 채운다', () {
    final marine = _hourlyBlock([
      'wave_height',
      'wave_period',
      'wave_direction',
      'sea_surface_temperature',
    ], 3);
    (marine['wave_height'] as List)[1] = null;
    final forecast = _hourlyBlock([
      'wind_speed_10m',
      'wind_gusts_10m',
      'wind_direction_10m',
      'temperature_2m',
    ], 3);

    final merged = mergeOpenMeteoHourly(
      marine: marine,
      forecast: forecast,
      maxHours: 3,
    );
    expect(merged[1].waveHeightM, merged[0].waveHeightM);
  });

  test('파고 예보 한계를 넘는 시각은 표에서 제외한다', () {
    // 바람(forecast)은 6시간, 파고(marine)는 마지막 2시각이 null(모델 한계 밖).
    final marine = _hourlyBlock([
      'wave_height',
      'wave_period',
      'wave_direction',
      'sea_surface_temperature',
    ], 6);
    (marine['wave_height'] as List)[4] = null;
    (marine['wave_height'] as List)[5] = null;
    final forecast = _hourlyBlock([
      'wind_speed_10m',
      'wind_gusts_10m',
      'wind_direction_10m',
      'temperature_2m',
    ], 6);

    final merged = mergeOpenMeteoHourly(
      marine: marine,
      forecast: forecast,
      maxHours: 6,
    );
    // 파고가 실제로 있는 마지막 시각(인덱스 3)까지만 남는다.
    expect(merged, hasLength(4));
  });

  test('API 오류 시 예외를 던진다 (폴백 래퍼가 처리)', () async {
    final repo = OpenMeteoMarineRepository(
      client: buildClient(marineStatus: 500),
    );
    expect(
      () => repo.fetchForecast(sampleLocations.first),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('파고는 앞 구간 ECMWF WAM, WAM 예보 한계 뒤는 GFS로 병합한다', () async {
    // WAM(Windy와 동일)은 앞 240시간(10일)만 값이 있고 그 뒤는 null,
    // GFS는 16일 전체에 값이 있다. 병합 결과는 앞구간=WAM, 뒷구간=GFS여야.
    const wamHorizon = 240;
    final client = MockClient((request) async {
      final times = List.generate(
        hours,
        (i) => DateTime(
          2026,
          7,
          15,
        ).add(Duration(hours: i)).toIso8601String().substring(0, 16),
      );
      if (request.url.host == 'marine-api.open-meteo.com') {
        final models = request.url.queryParameters['models'];
        if (models == 'ecmwf_wam025') {
          return http.Response(
            jsonEncode({
              'hourly': {
                'time': times,
                'wave_height': [
                  for (var i = 0; i < hours; i++) i < wamHorizon ? 5.0 : null,
                ],
              },
            }),
            200,
          );
        }
        if (models == 'ncep_gfswave025') {
          return http.Response(
            jsonEncode({
              'hourly': {'time': times, 'wave_height': List.filled(hours, 9.0)},
            }),
            200,
          );
        }
        // 모델 미지정 = 수온 호출.
        return http.Response(
          jsonEncode({
            'hourly': {
              'time': times,
              'sea_surface_temperature': List.filled(hours, 20.0),
            },
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'hourly': {
            'time': times,
            'wind_speed_10m': List.filled(hours, 3.0),
            'wind_gusts_10m': List.filled(hours, 6.0),
            'wind_direction_10m': List.filled(hours, 180.0),
            'temperature_2m': List.filled(hours, 25.0),
          },
        }),
        200,
      );
    });

    final repo = OpenMeteoMarineRepository(client: client);
    final forecast = await repo.fetchForecast(sampleLocations.first);
    // 앞 구간(0, 100시간): WAM 5.0.
    expect(forecast.hourly[0].waveHeightM, 5.0);
    expect(forecast.hourly[100].waveHeightM, 5.0);
    // WAM 한계(240) 뒤: GFS 9.0 — 16일 예보가 잘리지 않고 이어진다.
    expect(forecast.hourly[wamHorizon].waveHeightM, 9.0);
    expect(forecast.hourly[300].waveHeightM, 9.0);
    expect(forecast.hourly, hasLength(hours));
  });

  test('연안 육지 마스킹 지점(파고 0.0)은 가장 가까운 앞바다로 옮겨 재조회한다', () async {
    // 원점(경도 128.8)은 파고 0.0(육지 마스킹 — null이 아니라 0을 준다),
    // 앞바다(경도>128.9)는 값이 있다. 원점 조회 → 양의 파고 없음 → 동쪽
    // 앞바다로 옮겨 파고·바람을 재조회한다.
    final client = MockClient((request) async {
      final lon = double.parse(request.url.queryParameters['longitude']!);
      final wet = lon > 128.9;
      final n = int.parse(request.url.queryParameters['forecast_days']!) * 24;
      final times = List.generate(
        n,
        (i) => DateTime(
          2026,
          7,
          25,
        ).add(Duration(hours: i)).toIso8601String().substring(0, 16),
      );
      if (request.url.host == 'marine-api.open-meteo.com') {
        final keys = request.url.queryParameters['hourly']!.split(',');
        return http.Response(
          jsonEncode({
            'hourly': {
              'time': times,
              for (final k in keys)
                k: List.generate(
                  n,
                  (i) => wet
                      ? (k == 'sea_surface_temperature' ? 20.0 : 0.5)
                      : 0.0, // 육지 마스킹: null이 아니라 0.0
                ),
            },
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'hourly': {
            'time': times,
            'wind_speed_10m': List.filled(n, wet ? 2.0 : 4.0),
            'wind_gusts_10m': List.filled(n, 5.0),
            'wind_direction_10m': List.filled(n, 180.0),
            'temperature_2m': List.filled(n, 25.0),
          },
        }),
        200,
      );
    });

    final repo = OpenMeteoMarineRepository(client: client);
    const coastal = SeaLocation(
      id: 'tap',
      name: '탭 지점',
      region: '동해',
      latitude: 37.796,
      longitude: 128.8,
    );
    final forecast = await repo.fetchForecast(coastal, hours: 24);
    // 앞바다(129.1)로 옮겨져 파고·바람이 앞바다 값으로 나온다.
    expect(forecast.hourly.first.waveHeightM, closeTo(0.5, 1e-9));
    expect(forecast.hourly.first.windSpeedMs, closeTo(2.0, 1e-9));
  });

  test('WAM 호출이 실패해도 GFS만으로 정상 동작한다', () async {
    final client = MockClient((request) async {
      final times = List.generate(
        6,
        (i) => DateTime(
          2026,
          7,
          15,
        ).add(Duration(hours: i)).toIso8601String().substring(0, 16),
      );
      if (request.url.host == 'marine-api.open-meteo.com') {
        final models = request.url.queryParameters['models'];
        if (models == 'ecmwf_wam025') {
          return http.Response('boom', 500); // WAM만 실패.
        }
        if (models == 'ncep_gfswave025') {
          return http.Response(
            jsonEncode({
              'hourly': {'time': times, 'wave_height': List.filled(6, 7.0)},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'hourly': {
              'time': times,
              'sea_surface_temperature': List.filled(6, 20.0),
            },
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'hourly': {
            'time': times,
            'wind_speed_10m': List.filled(6, 3.0),
            'wind_gusts_10m': List.filled(6, 6.0),
            'wind_direction_10m': List.filled(6, 180.0),
            'temperature_2m': List.filled(6, 25.0),
          },
        }),
        200,
      );
    });

    final repo = OpenMeteoMarineRepository(client: client);
    final forecast = await repo.fetchForecast(sampleLocations.first, hours: 6);
    // WAM이 죽었으니 전 구간 GFS 값(7.0).
    expect(forecast.hourly.first.waveHeightM, 7.0);
    expect(forecast.hourly, hasLength(6));
  });
}
