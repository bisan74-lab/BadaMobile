import 'dart:convert';

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
}
