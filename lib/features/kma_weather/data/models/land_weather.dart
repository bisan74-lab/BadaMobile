// 육상(지역) 날씨 예보 모델. Open-Meteo Forecast/Air-Quality API를 기반으로
// 24시간·15일 예보와 부가정보(자외선·가시거리·습도·바람·일출몰·공기질·
// 2시간 강수)를 담는다. 기상청 단기예보가 있으면 근일 시간별 값에 덮어쓴다.

/// 시간별 값.
class WeatherHour {
  const WeatherHour({
    required this.time,
    required this.tempC,
    required this.weatherCode,
    required this.precipProbPct,
    required this.humidityPct,
    required this.windSpeedMs,
    required this.windGustMs,
    required this.windDirDeg,
  });

  final DateTime time;
  final double tempC;
  final int weatherCode;
  final int precipProbPct;
  final int humidityPct;
  final double windSpeedMs;
  final double windGustMs;
  final double windDirDeg;

  WeatherHour copyWith({double? tempC, int? weatherCode}) => WeatherHour(
    time: time,
    tempC: tempC ?? this.tempC,
    weatherCode: weatherCode ?? this.weatherCode,
    precipProbPct: precipProbPct,
    humidityPct: humidityPct,
    windSpeedMs: windSpeedMs,
    windGustMs: windGustMs,
    windDirDeg: windDirDeg,
  );

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'tempC': tempC,
    'weatherCode': weatherCode,
    'precipProbPct': precipProbPct,
    'humidityPct': humidityPct,
    'windSpeedMs': windSpeedMs,
    'windGustMs': windGustMs,
    'windDirDeg': windDirDeg,
  };

  factory WeatherHour.fromJson(Map<String, dynamic> j) => WeatherHour(
    time: DateTime.parse(j['time'] as String),
    tempC: (j['tempC'] as num).toDouble(),
    weatherCode: j['weatherCode'] as int,
    precipProbPct: j['precipProbPct'] as int,
    humidityPct: j['humidityPct'] as int,
    windSpeedMs: (j['windSpeedMs'] as num).toDouble(),
    windGustMs: (j['windGustMs'] as num).toDouble(),
    windDirDeg: (j['windDirDeg'] as num).toDouble(),
  );
}

/// 일별 요약(최대 15일).
class WeatherDay {
  const WeatherDay({
    required this.date,
    required this.weatherCode,
    required this.tempMinC,
    required this.tempMaxC,
    required this.precipProbMaxPct,
    required this.uvMax,
    this.sunrise,
    this.sunset,
  });

  final DateTime date;
  final int weatherCode;
  final double tempMinC;
  final double tempMaxC;
  final int precipProbMaxPct;
  final double uvMax;
  final DateTime? sunrise;
  final DateTime? sunset;

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'weatherCode': weatherCode,
    'tempMinC': tempMinC,
    'tempMaxC': tempMaxC,
    'precipProbMaxPct': precipProbMaxPct,
    'uvMax': uvMax,
    'sunrise': sunrise?.toIso8601String(),
    'sunset': sunset?.toIso8601String(),
  };

  factory WeatherDay.fromJson(Map<String, dynamic> j) => WeatherDay(
    date: DateTime.parse(j['date'] as String),
    weatherCode: j['weatherCode'] as int,
    tempMinC: (j['tempMinC'] as num).toDouble(),
    tempMaxC: (j['tempMaxC'] as num).toDouble(),
    precipProbMaxPct: j['precipProbMaxPct'] as int,
    uvMax: (j['uvMax'] as num).toDouble(),
    sunrise: j['sunrise'] == null
        ? null
        : DateTime.parse(j['sunrise'] as String),
    sunset: j['sunset'] == null ? null : DateTime.parse(j['sunset'] as String),
  );
}

/// 현재값 + 부가정보.
class WeatherNow {
  const WeatherNow({
    required this.tempC,
    required this.weatherCode,
    required this.humidityPct,
    required this.windSpeedMs,
    required this.windGustMs,
    required this.windDirDeg,
    required this.uvIndex,
    required this.visibilityKm,
    required this.feelsLikeC,
  });

  final double tempC;
  final int weatherCode;
  final int humidityPct;
  final double windSpeedMs;
  final double windGustMs;
  final double windDirDeg;
  final double uvIndex;
  final double visibilityKm;
  final double feelsLikeC;

  Map<String, dynamic> toJson() => {
    'tempC': tempC,
    'weatherCode': weatherCode,
    'humidityPct': humidityPct,
    'windSpeedMs': windSpeedMs,
    'windGustMs': windGustMs,
    'windDirDeg': windDirDeg,
    'uvIndex': uvIndex,
    'visibilityKm': visibilityKm,
    'feelsLikeC': feelsLikeC,
  };

  factory WeatherNow.fromJson(Map<String, dynamic> j) => WeatherNow(
    tempC: (j['tempC'] as num).toDouble(),
    weatherCode: j['weatherCode'] as int,
    humidityPct: j['humidityPct'] as int,
    windSpeedMs: (j['windSpeedMs'] as num).toDouble(),
    windGustMs: (j['windGustMs'] as num).toDouble(),
    windDirDeg: (j['windDirDeg'] as num).toDouble(),
    uvIndex: (j['uvIndex'] as num).toDouble(),
    visibilityKm: (j['visibilityKm'] as num).toDouble(),
    feelsLikeC: (j['feelsLikeC'] as num).toDouble(),
  );
}

/// 공기질(대기오염) 예측.
class AirQuality {
  const AirQuality({required this.pm2_5, required this.pm10, this.aqi});

  final double pm2_5;
  final double pm10;

  /// European AQI(있으면).
  final int? aqi;

  /// PM2.5(㎍/㎥) 기준 4단계 한글 등급.
  String get gradeKo {
    if (pm2_5 <= 15) return '좋음';
    if (pm2_5 <= 35) return '보통';
    if (pm2_5 <= 75) return '나쁨';
    return '매우나쁨';
  }

  Map<String, dynamic> toJson() => {'pm2_5': pm2_5, 'pm10': pm10, 'aqi': aqi};

  factory AirQuality.fromJson(Map<String, dynamic> j) => AirQuality(
    pm2_5: (j['pm2_5'] as num).toDouble(),
    pm10: (j['pm10'] as num).toDouble(),
    aqi: (j['aqi'] as num?)?.toInt(),
  );
}

/// 2시간 이내 강수 예보 한 스텝(15분 간격).
class NowcastStep {
  const NowcastStep({
    required this.time,
    required this.precipMm,
    required this.weatherCode,
  });

  final DateTime time;
  final double precipMm;
  final int weatherCode;

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'precipMm': precipMm,
    'weatherCode': weatherCode,
  };

  factory NowcastStep.fromJson(Map<String, dynamic> j) => NowcastStep(
    time: DateTime.parse(j['time'] as String),
    precipMm: (j['precipMm'] as num).toDouble(),
    weatherCode: j['weatherCode'] as int,
  );
}

/// 지역 날씨 예보 묶음.
class WeatherForecast {
  const WeatherForecast({
    required this.locationId,
    required this.now,
    required this.hourly,
    required this.daily,
    this.air,
    this.nowcast = const [],
  });

  final String locationId;
  final WeatherNow now;
  final List<WeatherHour> hourly;
  final List<WeatherDay> daily;
  final AirQuality? air;

  /// 향후 2시간 15분 간격 강수(있으면).
  final List<NowcastStep> nowcast;

  /// 현재 시각 이후의 24시간치 시간별.
  List<WeatherHour> get next24h {
    final now = DateTime.now();
    return hourly
        .where((h) => h.time.isAfter(now.subtract(const Duration(hours: 1))))
        .take(24)
        .toList();
  }

  Map<String, dynamic> toJson() => {
    'locationId': locationId,
    'now': now.toJson(),
    'hourly': hourly.map((h) => h.toJson()).toList(),
    'daily': daily.map((d) => d.toJson()).toList(),
    'air': air?.toJson(),
    'nowcast': nowcast.map((n) => n.toJson()).toList(),
  };

  factory WeatherForecast.fromJson(Map<String, dynamic> j) => WeatherForecast(
    locationId: j['locationId'] as String,
    now: WeatherNow.fromJson(j['now'] as Map<String, dynamic>),
    hourly: (j['hourly'] as List)
        .map((h) => WeatherHour.fromJson(h as Map<String, dynamic>))
        .toList(),
    daily: (j['daily'] as List)
        .map((d) => WeatherDay.fromJson(d as Map<String, dynamic>))
        .toList(),
    air: j['air'] == null
        ? null
        : AirQuality.fromJson(j['air'] as Map<String, dynamic>),
    nowcast: ((j['nowcast'] as List?) ?? const [])
        .map((n) => NowcastStep.fromJson(n as Map<String, dynamic>))
        .toList(),
  );
}
