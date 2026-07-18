import 'package:bada_mobile/features/kma_weather/data/models/land_weather.dart';
import 'package:bada_mobile/features/kma_weather/data/repositories/mock_land_weather_repository.dart';
import 'package:bada_mobile/features/kma_weather/data/weather_code.dart';
import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final repo = MockLandWeatherRepository();

  test('16일 시간별 + 15일 일별 + 나우캐스트 + 공기질을 반환한다', () async {
    final f = await repo.fetchForecast(sampleLocations.first);
    expect(f.hourly.length, 16 * 24);
    expect(f.daily.length, 15);
    expect(f.nowcast.length, 8);
    expect(f.air, isNotNull);
    expect(f.locationId, sampleLocations.first.id);
  });

  test('next24h는 24시간을 돌려주고 값이 타당하다', () async {
    final f = await repo.fetchForecast(sampleLocations.first);
    final next = f.next24h;
    expect(next.length, 24);
    for (final h in next) {
      expect(h.precipProbPct, inInclusiveRange(0, 100));
      expect(h.humidityPct, inInclusiveRange(0, 100));
      expect(h.windSpeedMs, greaterThanOrEqualTo(0));
    }
  });

  test('일별 요약은 최저<=최고, 일출<일몰', () async {
    final f = await repo.fetchForecast(sampleLocations.first);
    for (final d in f.daily) {
      expect(d.tempMinC, lessThanOrEqualTo(d.tempMaxC));
      if (d.sunrise != null && d.sunset != null) {
        expect(d.sunrise!.isBefore(d.sunset!), isTrue);
      }
    }
  });

  test('toJson/fromJson 왕복이 값을 보존한다', () async {
    final f = await repo.fetchForecast(sampleLocations.first);
    final restored = WeatherForecast.fromJson(f.toJson());
    expect(restored.hourly.length, f.hourly.length);
    expect(restored.daily.length, f.daily.length);
    expect(restored.now.tempC, f.now.tempC);
    expect(restored.air?.pm2_5, f.air?.pm2_5);
  });

  test('WMO 코드 매핑: 라벨과 아이콘 종류', () {
    expect(wmoLabelKo(0), '맑음');
    expect(wmoLabelKo(63), '비');
    expect(wmoLabelKo(73), '눈');
    expect(wmoIcon(0), WeatherIconKind.clear);
    expect(wmoIcon(95), WeatherIconKind.thunder);
    expect(precipKindKo(0), isNull);
    expect(precipKindKo(63), '비');
  });

  test('기상청 SKY/PTY → WMO 근사 변환', () {
    expect(kmaToWmo(sky: 1, pty: 0), 0); // 맑음
    expect(kmaToWmo(sky: 4, pty: 0), 3); // 흐림
    expect(wmoIcon(kmaToWmo(sky: 1, pty: 1)), WeatherIconKind.rain); // 비
    expect(wmoIcon(kmaToWmo(sky: 1, pty: 3)), WeatherIconKind.snow); // 눈
  });
}
