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

  test('주기 0초짜리 너울(모델이 못 낸 값)은 직전 값으로 잇는다', () {
    // GFS Wave는 값을 못 낼 때 null이 아니라 0.0m/0.0s를 준다(실측). 그대로
    // 두면 표·지도에 "너울 0.0m·0s"가 찍혀 회귀 방지로 고정한다.
    final marine = _hourlyBlock([
      'wave_height',
      'wave_period',
      'wave_direction',
      'sea_surface_temperature',
      'swell_wave_height',
      'swell_wave_period',
    ], 4);
    (marine['swell_wave_height'] as List)[2] = 0.0;
    (marine['swell_wave_period'] as List)[2] = 0.0;
    final forecast = _hourlyBlock([
      'wind_speed_10m',
      'wind_gusts_10m',
      'wind_direction_10m',
      'temperature_2m',
    ], 4);

    final merged = mergeOpenMeteoHourly(
      marine: marine,
      forecast: forecast,
      maxHours: 4,
    );
    // 0.0/0.0s 자리는 직전 시각 값을 그대로 잇는다.
    expect(merged[2].swellHeightM, merged[1].swellHeightM);
    expect(merged[2].swellPeriodS, merged[1].swellPeriodS);
    expect(merged[2].swellPeriodS, greaterThan(0));
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

  test('총 파고는 0이어도 너울(swell)이 있으면 그 지점 자체를 바다로 인정한다'
      '(회귀 방지: 강릉·사천진처럼 총 파고만 격자 마스킹으로 0이고 너울은 '
      '살아있는 연안 지점이 육지로 오판되던 문제)', () async {
    final client = MockClient((request) async {
      final n = int.parse(request.url.queryParameters['forecast_days']!) * 24;
      final times = List.generate(
        n,
        (i) => DateTime(
          2026,
          7,
          30,
        ).add(Duration(hours: i)).toIso8601String().substring(0, 16),
      );
      if (request.url.host == 'marine-api.open-meteo.com') {
        final keys = request.url.queryParameters['hourly']!.split(',');
        return http.Response(
          jsonEncode({
            'hourly': {
              'time': times,
              for (final k in keys)
                // 총 파고(wave_height)는 0(격자 마스킹)이지만 2차 너울은
                // 실제 값(0.2)이 있다 — 실측(위도 37.805 지점)과 같은 패턴.
                k: List.filled(
                  n,
                  k == 'secondary_swell_wave_height' ? 0.2 : 0.0,
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
            'wind_speed_10m': List.filled(n, 6.0),
            'wind_gusts_10m': List.filled(n, 8.0),
            'wind_direction_10m': List.filled(n, 180.0),
            'temperature_2m': List.filled(n, 27.0),
          },
        }),
        200,
      );
    });

    final repo = OpenMeteoMarineRepository(client: client);
    const nearShore = SeaLocation(
      id: 'gangneung',
      name: '강릉 앞바다',
      region: '동해',
      latitude: 37.805,
      longitude: 128.9,
    );
    final forecast = await repo.fetchForecast(nearShore, hours: 24);
    // _nearestWetPoint 재조회 없이 원점 데이터 그대로 바다로 인정된다.
    expect(forecast.hasWaveData, isTrue);
    expect(forecast.hourly.first.swell2HeightM, closeTo(0.2, 1e-9));
  });

  test('주변에 앞바다가 없는 육지 지점은 hasWaveData=false', () async {
    // 모든 지점(원점·재조회 후보)에서 파고가 0.0 → 앞바다를 못 찾음 → 육지.
    final client = MockClient((request) async {
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
              for (final k in keys) k: List.filled(n, 0.0),
            },
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'hourly': {
            'time': times,
            'wind_speed_10m': List.filled(n, 3.0),
            'wind_gusts_10m': List.filled(n, 5.0),
            'wind_direction_10m': List.filled(n, 180.0),
            'temperature_2m': List.filled(n, 25.0),
          },
        }),
        200,
      );
    });

    final repo = OpenMeteoMarineRepository(client: client);
    const inland = SeaLocation(
      id: 'land',
      name: '내륙',
      region: '내륙',
      latitude: 37.5,
      longitude: 127.5,
      inland: true,
    );
    final forecast = await repo.fetchForecast(inland, hours: 24);
    expect(forecast.hasWaveData, isFalse);
    // 바람 등 육상값은 그대로 있다.
    expect(forecast.hourly.first.windSpeedMs, closeTo(3.0, 1e-9));
  });

  test('바다가 멀리(재조회 반경 밖)에만 있으면 그 먼바다를 끌어오지 않고 육지로 '
      '판정한다(회귀 방지: 예전엔 반경 1.0°까지 찾아 내륙도 먼바다 값을 보여줬다)', () async {
    // 원점(경도 127.5)은 파고 0.0. "바다"는 재조회 반경(최대 0.4°) 훨씬
    // 밖인 경도 128.6(=1.1° 차이)에만 있다 — 예전 반경(최대 1.0°)이었다면
    // 여전히 찾아냈을 거리.
    final client = MockClient((request) async {
      final lon = double.parse(request.url.queryParameters['longitude']!);
      final wet = (lon - 127.5).abs() > 1.0;
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
              for (final k in keys) k: List.filled(n, wet ? 0.5 : 0.0),
            },
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'hourly': {
            'time': times,
            'wind_speed_10m': List.filled(n, 3.0),
            'wind_gusts_10m': List.filled(n, 5.0),
            'wind_direction_10m': List.filled(n, 180.0),
            'temperature_2m': List.filled(n, 25.0),
          },
        }),
        200,
      );
    });

    final repo = OpenMeteoMarineRepository(client: client);
    const deepInland = SeaLocation(
      id: 'deep',
      name: '내륙 깊은 곳',
      region: '내륙',
      latitude: 37.5,
      longitude: 127.5,
    );
    final forecast = await repo.fetchForecast(deepInland, hours: 24);
    expect(forecast.hasWaveData, isFalse);
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
