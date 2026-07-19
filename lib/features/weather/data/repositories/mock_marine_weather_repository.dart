import 'dart:math' as math;

import '../../../locations/data/models/sea_location.dart';
import '../models/marine_weather.dart';
import 'marine_weather_repository.dart';

/// 합성 해양 기상 리포지토리.
///
/// 지점 좌표를 시드로 하는 부드러운 사인 조합으로 그럴듯한
/// 바람·파고·파주기·수온 시계열을 만든다 (재현 가능, 네트워크 불필요).
/// 실데이터(Open-Meteo) 호출 실패 시 폴백으로도 사용된다.
class MockMarineWeatherRepository implements MarineWeatherRepository {
  @override
  Future<MarineForecast> fetchForecast(
    SeaLocation location, {
    int hours = defaultForecastHours,
    int pastDays = 0,
  }) async {
    final seed = (location.latitude * 7 + location.longitude * 13) % 10;
    final start = DateTime.now().subtract(Duration(days: pastDays));
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
      // 파주기는 파고와 느슨하게 비례 (풍랑 4~6초, 너울 7~10초 수준).
      final period = 4.0 + 2.5 * wave + 0.8 * math.sin(x / 23);
      // 너울은 전체 파고의 일부(멀리서 온 성분)이고 주기는 더 길다.
      final swell = math.max(
        0.1,
        wave * (0.45 + 0.2 * math.sin(x / 19 + seed)),
      );
      final swellPeriod = period + 2.5 + 1.5 * math.sin(x / 21);
      final waveDirection = (direction + 25 * math.sin(x / 13) + 360) % 360;
      final waterTemp = 21 + 2 * math.sin(x / 30 + seed);
      final airTemp =
          24 +
          4 * math.sin(2 * math.pi * (t.hour - 9) / 24) +
          0.5 * math.sin(x / 13);
      // 풍파(WIND)는 현지 바람 성분, 2차 너울(SWELL2)은 약한 부성분.
      final windWave = math.max(0.1, wave - swell);
      final swell2 = math.max(0.05, swell * (0.4 + 0.15 * math.sin(x / 27)));
      final swell2Dir = (waveDirection + 60 * math.sin(x / 15) + 360) % 360;
      // 대략적인 날씨 코드(맑음↔구름↔비)를 시드로 순환시킨다.
      const codes = [0, 1, 2, 3, 45, 51, 61, 63, 80, 95];
      final code = codes[(x.abs().floor() + seed.floor()) % codes.length];

      return HourlyMarine(
        time: t,
        windSpeedMs: double.parse(math.max(0.3, wind).toStringAsFixed(1)),
        windGustMs: double.parse(
          (math.max(0.3, wind) * gustFactor).toStringAsFixed(1),
        ),
        windDirectionDeg: double.parse(direction.toStringAsFixed(0)),
        waveHeightM: double.parse(wave.toStringAsFixed(1)),
        wavePeriodS: double.parse(period.toStringAsFixed(1)),
        waveDirectionDeg: double.parse(waveDirection.toStringAsFixed(0)),
        waterTempC: double.parse(waterTemp.toStringAsFixed(1)),
        airTempC: double.parse(airTemp.toStringAsFixed(1)),
        swellHeightM: double.parse(swell.toStringAsFixed(1)),
        swellPeriodS: double.parse(swellPeriod.toStringAsFixed(1)),
        windWaveHeightM: double.parse(windWave.toStringAsFixed(1)),
        windWaveDirectionDeg: double.parse(direction.toStringAsFixed(0)),
        swellDirectionDeg: double.parse(waveDirection.toStringAsFixed(0)),
        swell2HeightM: double.parse(swell2.toStringAsFixed(1)),
        swell2PeriodS: double.parse((swellPeriod + 3).toStringAsFixed(1)),
        swell2DirectionDeg: double.parse(swell2Dir.toStringAsFixed(0)),
        weatherCode: code,
      );
    });

    return MarineForecast(locationId: location.id, hourly: hourly);
  }
}
