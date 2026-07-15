/// 시간별 해양 기상 예보 값.
class HourlyMarine {
  const HourlyMarine({
    required this.time,
    required this.windSpeedMs,
    required this.windGustMs,
    required this.windDirectionDeg,
    required this.waveHeightM,
    required this.wavePeriodS,
    required this.waveDirectionDeg,
    required this.waterTempC,
    required this.airTempC,
  });

  final DateTime time;
  final double windSpeedMs;
  final double windGustMs;

  /// 바람이 불어오는 방향 (기상 관례, 도).
  final double windDirectionDeg;
  final double waveHeightM;

  /// 파주기 (초).
  final double wavePeriodS;

  /// 파도가 밀려오는 방향 (도).
  final double waveDirectionDeg;
  final double waterTempC;
  final double airTempC;
}

/// 특정 지점의 해양 기상 예보 묶음.
class MarineForecast {
  const MarineForecast({required this.locationId, required this.hourly});

  final String locationId;

  /// 현재 시각부터 시간순.
  final List<HourlyMarine> hourly;

  HourlyMarine get current => hourly.first;

  /// 예보가 며칠치인지 (부분 일 포함 올림).
  int get forecastDays {
    if (hourly.isEmpty) return 0;
    final span = hourly.last.time.difference(hourly.first.time);
    return (span.inHours / 24).ceil();
  }
}
