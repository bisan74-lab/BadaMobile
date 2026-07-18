import 'package:bada_mobile/features/kma_weather/data/models/kma_forecast.dart';
import 'package:bada_mobile/features/kma_weather/data/repositories/mock_kma_weather_repository.dart';
import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final repo = MockKmaWeatherRepository();

  test('3일치(72시간) 시간별 예보를 반환한다', () async {
    final forecast = await repo.fetchForecast(sampleLocations.first);
    expect(forecast.hourly, hasLength(72));
    expect(forecast.locationId, sampleLocations.first.id);
  });

  test('예보 값이 타당한 범위에 있다', () async {
    final forecast = await repo.fetchForecast(sampleLocations.first);
    for (final h in forecast.hourly) {
      expect(h.popPercent, inInclusiveRange(0, 100));
      expect(h.humidityPercent, inInclusiveRange(0, 100));
      expect(h.windSpeedMs, greaterThanOrEqualTo(0));
      expect(skyLabelKo(h.skyCode), isNot('-'));
    }
  });

  test('일자별 요약이 최저/최고 기온과 대표값을 낸다', () async {
    final forecast = await repo.fetchForecast(sampleLocations.first);
    final days = forecast.dailySummaries;
    expect(days.length, greaterThanOrEqualTo(3));
    for (final day in days) {
      expect(day.minTempC, lessThanOrEqualTo(day.maxTempC));
      expect(day.hourly, isNotEmpty);
      expect(day.representative, isA<KmaHourly>());
    }
  });

  test('toJson/fromJson 왕복이 값을 보존한다', () async {
    final forecast = await repo.fetchForecast(sampleLocations.first);
    final restored = KmaForecast.fromJson(forecast.toJson());
    expect(restored.locationId, forecast.locationId);
    expect(restored.hourly.length, forecast.hourly.length);
    expect(restored.hourly.first.tempC, forecast.hourly.first.tempC);
  });
}
