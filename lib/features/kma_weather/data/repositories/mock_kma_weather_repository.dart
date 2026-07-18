import 'dart:math' as math;

import '../../../locations/data/models/sea_location.dart';
import '../models/kma_forecast.dart';
import 'kma_weather_repository.dart';

/// 합성 육상 날씨 리포지토리(기상청 단기예보 실패 시 폴백, 오프라인/테스트용).
/// 지점 좌표를 시드로 하는 사인 조합으로 그럴듯한 기온·하늘상태를 만든다.
class MockKmaWeatherRepository implements KmaWeatherRepository {
  static const _hours = 3 * 24;

  @override
  Future<KmaForecast> fetchForecast(SeaLocation location) async {
    final seed = (location.latitude * 9 + location.longitude * 5) % 10;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, now.hour);

    final hourly = List<KmaHourly>.generate(_hours, (i) {
      final t = start.add(Duration(hours: i));
      final x = i + seed;
      final tempC =
          19 + 6 * math.sin(2 * math.pi * (t.hour - 9) / 24) + math.sin(x / 11);
      final popPercent = (30 + 30 * math.sin(x / 7 + seed))
          .clamp(0, 100)
          .round();
      final skyCode = switch ((math.sin(x / 9 + seed) * 2).round()) {
        <= -1 => 4,
        0 => 3,
        _ => 1,
      };
      final ptyCode = popPercent > 60
          ? (t.month >= 12 || t.month <= 2 ? 3 : 1)
          : 0;
      return KmaHourly(
        time: t,
        tempC: double.parse(tempC.toStringAsFixed(1)),
        skyCode: skyCode,
        ptyCode: ptyCode,
        popPercent: popPercent,
        humidityPercent: (55 + 20 * math.sin(x / 13 + seed))
            .clamp(0, 100)
            .round(),
        windSpeedMs: double.parse(
          (3 + 2 * math.sin(x / 6 + seed).abs()).toStringAsFixed(1),
        ),
      );
    });

    return KmaForecast(locationId: location.id, hourly: hourly);
  }
}
