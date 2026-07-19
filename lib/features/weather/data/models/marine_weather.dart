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
    this.swellHeightM = 0,
    this.swellPeriodS = 0,
    this.windWaveHeightM = 0,
    this.windWaveDirectionDeg = 0,
    this.swellDirectionDeg = 0,
    this.swell2HeightM = 0,
    this.swell2PeriodS = 0,
    this.swell2DirectionDeg = 0,
    this.weatherCode = 0,
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

  /// 너울(swell) 파고 (m) — 멀리서 온 긴 주기 파도. 서핑 판단의 핵심.
  final double swellHeightM;

  /// 너울 주기 (초).
  final double swellPeriodS;

  /// 풍파(WIND) 파고 (m) — 현지 바람이 만든 파도.
  final double windWaveHeightM;

  /// 풍파가 밀려오는 방향 (도).
  final double windWaveDirectionDeg;

  /// 1차 너울(SWELL)이 밀려오는 방향 (도).
  final double swellDirectionDeg;

  /// 2차 너울(SWELL2) 파고 (m).
  final double swell2HeightM;

  /// 2차 너울 주기 (초).
  final double swell2PeriodS;

  /// 2차 너울이 밀려오는 방향 (도).
  final double swell2DirectionDeg;

  /// WMO 날씨 코드(맑음·구름·비·번개 등 아이콘용).
  final int weatherCode;

  /// 파력(Wave power, kW/m). 심해 파에너지 플럭스 근사식
  /// P ≈ 0.49 · H² · T (H=유의파고 m, T=파주기 s)로 계산한다.
  double get wavePowerKw => 0.49 * waveHeightM * waveHeightM * wavePeriodS;

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'windSpeedMs': windSpeedMs,
    'windGustMs': windGustMs,
    'windDirectionDeg': windDirectionDeg,
    'waveHeightM': waveHeightM,
    'wavePeriodS': wavePeriodS,
    'waveDirectionDeg': waveDirectionDeg,
    'waterTempC': waterTempC,
    'airTempC': airTempC,
    'swellHeightM': swellHeightM,
    'swellPeriodS': swellPeriodS,
    'windWaveHeightM': windWaveHeightM,
    'windWaveDirectionDeg': windWaveDirectionDeg,
    'swellDirectionDeg': swellDirectionDeg,
    'swell2HeightM': swell2HeightM,
    'swell2PeriodS': swell2PeriodS,
    'swell2DirectionDeg': swell2DirectionDeg,
    'weatherCode': weatherCode,
  };

  factory HourlyMarine.fromJson(Map<String, dynamic> json) => HourlyMarine(
    time: DateTime.parse(json['time'] as String),
    windSpeedMs: (json['windSpeedMs'] as num).toDouble(),
    windGustMs: (json['windGustMs'] as num).toDouble(),
    windDirectionDeg: (json['windDirectionDeg'] as num).toDouble(),
    waveHeightM: (json['waveHeightM'] as num).toDouble(),
    wavePeriodS: (json['wavePeriodS'] as num).toDouble(),
    waveDirectionDeg: (json['waveDirectionDeg'] as num).toDouble(),
    waterTempC: (json['waterTempC'] as num).toDouble(),
    airTempC: (json['airTempC'] as num).toDouble(),
    // 예전 캐시에는 없을 수 있어 기본 0으로 흡수한다.
    swellHeightM: (json['swellHeightM'] as num?)?.toDouble() ?? 0,
    swellPeriodS: (json['swellPeriodS'] as num?)?.toDouble() ?? 0,
    windWaveHeightM: (json['windWaveHeightM'] as num?)?.toDouble() ?? 0,
    windWaveDirectionDeg:
        (json['windWaveDirectionDeg'] as num?)?.toDouble() ?? 0,
    swellDirectionDeg: (json['swellDirectionDeg'] as num?)?.toDouble() ?? 0,
    swell2HeightM: (json['swell2HeightM'] as num?)?.toDouble() ?? 0,
    swell2PeriodS: (json['swell2PeriodS'] as num?)?.toDouble() ?? 0,
    swell2DirectionDeg: (json['swell2DirectionDeg'] as num?)?.toDouble() ?? 0,
    weatherCode: (json['weatherCode'] as num?)?.toInt() ?? 0,
  );
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

  Map<String, dynamic> toJson() => {
    'locationId': locationId,
    'hourly': hourly.map((h) => h.toJson()).toList(),
  };

  factory MarineForecast.fromJson(Map<String, dynamic> json) => MarineForecast(
    locationId: json['locationId'] as String,
    hourly: (json['hourly'] as List)
        .map((h) => HourlyMarine.fromJson(h as Map<String, dynamic>))
        .toList(),
  );
}
