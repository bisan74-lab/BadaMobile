import 'dart:math' as math;

import '../../../locations/data/models/sea_location.dart';
import '../models/marine_weather.dart';
import 'marine_weather_repository.dart';

/// 합성 해양 기상 리포지토리.
///
/// 지점 좌표를 시드로 하는 부드러운 사인 조합으로 그럴듯한
/// 바람·파고·수온 시계열을 만든다 (재현 가능, 네트워크 불필요).
class MockMarineWeatherRepository implements MarineWeatherRepository {
  @override
  Future<MarineForecast> fetchForecast(
    SeaLocation location, {
    int hours = 48,
  }) async {
    final seed = (location.latitude * 7 + location.longitude * 13) % 10;
    final start = DateTime.now();
    final startHour = DateTime(start.year, start.month, start.day, start.hour);

    final hourly = List<HourlyMarine>.generate(hours, (i) {
      final t = startHour.add(Duration(hours: i));
      final x =
          (t.millisecondsSinceEpoch / Duration.millisecondsPerHour + seed);

      final wind = 4.5 + 3.0 * math.sin(x / 9) + 1.5 * math.sin(x / 3.7 + seed);
      final gustFactor = 1.3 + 0.2 * math.sin(x / 5);
      final direction = (200 + 80 * math.sin(x / 17) + seed * 10) % 360;
      final wave = math.max(
        0.2,
        0.8 + 0.6 * math.sin(x / 11 + 1) + 0.2 * math.sin(x / 4),
      );
      final waterTemp = 21 + 2 * math.sin(x / 30 + seed);
      final airTemp =
          24 +
          4 * math.sin(2 * math.pi * (t.hour - 9) / 24) +
          0.5 * math.sin(x / 13);

      return HourlyMarine(
        time: t,
        windSpeedMs: double.parse(math.max(0.3, wind).toStringAsFixed(1)),
        windGustMs: double.parse(
          (math.max(0.3, wind) * gustFactor).toStringAsFixed(1),
        ),
        windDirectionDeg: double.parse(direction.toStringAsFixed(0)),
        waveHeightM: double.parse(wave.toStringAsFixed(1)),
        waterTempC: double.parse(waterTemp.toStringAsFixed(1)),
        airTempC: double.parse(airTemp.toStringAsFixed(1)),
      );
    });

    return MarineForecast(locationId: location.id, hourly: hourly);
  }
}
