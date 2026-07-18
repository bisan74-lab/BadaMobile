import 'dart:math' as math;

import '../../../locations/data/models/sea_location.dart';
import '../models/land_weather.dart';
import 'land_weather_repository.dart';

/// 합성 육상 날씨 리포지토리(오프라인/테스트/폴백).
/// 좌표 시드 기반 사인 조합으로 24시간·15일 예보와 부가정보를 만든다.
class MockLandWeatherRepository implements LandWeatherRepository {
  @override
  Future<WeatherForecast> fetchForecast(SeaLocation location) async {
    final seed = (location.latitude * 9 + location.longitude * 5) % 10;
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, now.hour);

    int codeFor(double x, int pop) {
      if (pop > 65) {
        return (now.month >= 12 || now.month <= 2) ? 73 : 63;
      }
      return switch ((math.sin(x / 9 + seed) * 2).round()) {
        <= -1 => 3,
        0 => 2,
        _ => (math.sin(x / 5) > 0.6 ? 1 : 0),
      };
    }

    final hourly = List<WeatherHour>.generate(16 * 24, (i) {
      final t = start.add(Duration(hours: i));
      final x = i + seed;
      final temp =
          18 +
          7 * math.sin(2 * math.pi * (t.hour - 9) / 24) +
          math.sin(x / 11) +
          2 * math.sin(x / 90);
      final pop = (30 + 35 * math.sin(x / 7 + seed)).clamp(0, 100).round();
      return WeatherHour(
        time: t,
        tempC: double.parse(temp.toStringAsFixed(1)),
        weatherCode: codeFor(x.toDouble(), pop),
        precipProbPct: pop,
        humidityPct: (60 + 20 * math.sin(x / 13 + seed)).clamp(0, 100).round(),
        windSpeedMs: double.parse(
          (2 + 2.5 * math.sin(x / 6 + seed).abs()).toStringAsFixed(1),
        ),
        windGustMs: double.parse(
          (4 + 3 * math.sin(x / 6 + seed).abs()).toStringAsFixed(1),
        ),
        windDirDeg: (200 + 80 * math.sin(x / 17)) % 360,
      );
    });

    final daily = List<WeatherDay>.generate(15, (d) {
      final date = DateTime(
        now.year,
        now.month,
        now.day,
      ).add(Duration(days: d));
      final dayHours = hourly.where(
        (h) =>
            h.time.year == date.year &&
            h.time.month == date.month &&
            h.time.day == date.day,
      );
      final temps = dayHours.map((h) => h.tempC).toList();
      final pops = dayHours.map((h) => h.precipProbPct).toList();
      final codes = dayHours.map((h) => h.weatherCode).toList();
      return WeatherDay(
        date: date,
        weatherCode: codes.isEmpty ? 1 : codes[codes.length ~/ 2],
        tempMinC: temps.isEmpty ? 15 : temps.reduce(math.min),
        tempMaxC: temps.isEmpty ? 22 : temps.reduce(math.max),
        precipProbMaxPct: pops.isEmpty ? 0 : pops.reduce(math.max),
        uvMax: double.parse(
          (3 + 4 * math.sin(d + seed).abs()).toStringAsFixed(1),
        ),
        sunrise: DateTime(date.year, date.month, date.day, 6, 10),
        sunset: DateTime(date.year, date.month, date.day, 19, 20),
      );
    });

    final h0 = hourly.first;
    final nowVal = WeatherNow(
      tempC: h0.tempC,
      weatherCode: h0.weatherCode,
      humidityPct: h0.humidityPct,
      windSpeedMs: h0.windSpeedMs,
      windGustMs: h0.windGustMs,
      windDirDeg: h0.windDirDeg,
      uvIndex: daily.first.uvMax,
      visibilityKm: double.parse((12 + 6 * math.sin(seed)).toStringAsFixed(0)),
      feelsLikeC: double.parse((h0.tempC - 1).toStringAsFixed(1)),
    );

    final nowcast = List<NowcastStep>.generate(8, (i) {
      final t = start.add(Duration(minutes: 15 * (i + 1)));
      final wet = math.sin(i / 2 + seed) > 0.4;
      return NowcastStep(
        time: t,
        precipMm: wet ? double.parse((0.3 + i * 0.15).toStringAsFixed(1)) : 0,
        weatherCode: wet ? 61 : 1,
      );
    });

    return WeatherForecast(
      locationId: location.id,
      now: nowVal,
      hourly: hourly,
      daily: daily,
      nowcast: nowcast,
      air: AirQuality(
        pm2_5: double.parse(
          (12 + 20 * math.sin(seed).abs()).toStringAsFixed(0),
        ),
        pm10: double.parse(
          (25 + 30 * math.sin(seed + 1).abs()).toStringAsFixed(0),
        ),
        aqi: (30 + 40 * math.sin(seed).abs()).round(),
      ),
    );
  }
}
