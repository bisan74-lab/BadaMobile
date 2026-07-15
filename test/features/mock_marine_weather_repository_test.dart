import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:bada_mobile/features/weather/data/repositories/mock_marine_weather_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final repo = MockMarineWeatherRepository();

  test('기본으로 16일(384시간) 예보를 반환한다 — 최소 2주 요건', () async {
    final forecast = await repo.fetchForecast(sampleLocations.first);
    expect(forecast.hourly, hasLength(16 * 24));
    expect(forecast.forecastDays, greaterThanOrEqualTo(14));
    expect(forecast.locationId, sampleLocations.first.id);
  });

  test('요청한 시간 수만큼 시간별 예보를 반환한다', () async {
    final forecast = await repo.fetchForecast(sampleLocations.first, hours: 48);
    expect(forecast.hourly, hasLength(48));
  });

  test('예보 값이 물리적으로 타당한 범위에 있다', () async {
    final forecast = await repo.fetchForecast(sampleLocations.first);
    for (final h in forecast.hourly) {
      expect(h.windSpeedMs, greaterThanOrEqualTo(0));
      expect(h.windGustMs, greaterThanOrEqualTo(h.windSpeedMs));
      expect(h.windDirectionDeg, inInclusiveRange(0, 360));
      expect(h.waveHeightM, greaterThanOrEqualTo(0));
      expect(h.wavePeriodS, inInclusiveRange(1, 20));
      expect(h.waveDirectionDeg, inInclusiveRange(0, 360));
      expect(h.waterTempC, inInclusiveRange(-2, 35));
    }
  });

  test('시간이 1시간 간격으로 증가한다', () async {
    final forecast = await repo.fetchForecast(sampleLocations.first);
    for (var i = 1; i < forecast.hourly.length; i++) {
      expect(
        forecast.hourly[i].time.difference(forecast.hourly[i - 1].time),
        const Duration(hours: 1),
      );
    }
  });
}
