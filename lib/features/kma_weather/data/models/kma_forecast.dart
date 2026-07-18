/// 기상청 단기예보(하늘상태·강수·기온 등) 1시간 단위 값.
class KmaHourly {
  const KmaHourly({
    required this.time,
    required this.tempC,
    required this.skyCode,
    required this.ptyCode,
    required this.popPercent,
    required this.humidityPercent,
    required this.windSpeedMs,
  });

  final DateTime time;
  final double tempC;

  /// 하늘상태: 1=맑음, 3=구름많음, 4=흐림.
  final int skyCode;

  /// 강수형태: 0=없음, 1=비, 2=비/눈, 3=눈, 4=소나기(그 외 코드는 기타로 처리).
  final int ptyCode;

  /// 강수확률(%).
  final int popPercent;
  final int humidityPercent;
  final double windSpeedMs;

  Map<String, dynamic> toJson() => {
    'time': time.toIso8601String(),
    'tempC': tempC,
    'skyCode': skyCode,
    'ptyCode': ptyCode,
    'popPercent': popPercent,
    'humidityPercent': humidityPercent,
    'windSpeedMs': windSpeedMs,
  };

  factory KmaHourly.fromJson(Map<String, dynamic> json) => KmaHourly(
    time: DateTime.parse(json['time'] as String),
    tempC: (json['tempC'] as num).toDouble(),
    skyCode: json['skyCode'] as int,
    ptyCode: json['ptyCode'] as int,
    popPercent: json['popPercent'] as int,
    humidityPercent: json['humidityPercent'] as int,
    windSpeedMs: (json['windSpeedMs'] as num).toDouble(),
  );
}

/// 하늘상태 한글 표기.
String skyLabelKo(int skyCode) => switch (skyCode) {
  1 => '맑음',
  3 => '구름많음',
  4 => '흐림',
  _ => '-',
};

/// 강수형태 한글 표기. 강수형태가 "없음"이 아니면 이 표기가 하늘상태보다 우선한다.
String ptyLabelKo(int ptyCode) => switch (ptyCode) {
  0 => '없음',
  1 => '비',
  2 => '비/눈',
  3 => '눈',
  4 => '소나기',
  5 => '빗방울',
  6 => '빗방울눈날림',
  7 => '눈날림',
  _ => '-',
};

/// 지점별 기상청 단기예보 묶음(보통 발표 시점 기준 최대 3일치 시간별 자료).
class KmaForecast {
  const KmaForecast({required this.locationId, required this.hourly});

  final String locationId;

  /// 시간순.
  final List<KmaHourly> hourly;

  /// 날짜별로 묶어 그날의 최저/최고 기온과 대표(정오에 가장 가까운) 값을 낸다.
  List<KmaDaySummary> get dailySummaries {
    final byDate = <DateTime, List<KmaHourly>>{};
    for (final h in hourly) {
      final day = DateTime(h.time.year, h.time.month, h.time.day);
      byDate.putIfAbsent(day, () => []).add(h);
    }
    final days = byDate.keys.toList()..sort();
    return [
      for (final day in days)
        KmaDaySummary(
          date: day,
          hourly: byDate[day]!..sort((a, b) => a.time.compareTo(b.time)),
        ),
    ];
  }

  Map<String, dynamic> toJson() => {
    'locationId': locationId,
    'hourly': hourly.map((h) => h.toJson()).toList(),
  };

  factory KmaForecast.fromJson(Map<String, dynamic> json) => KmaForecast(
    locationId: json['locationId'] as String,
    hourly: (json['hourly'] as List)
        .map((h) => KmaHourly.fromJson(h as Map<String, dynamic>))
        .toList(),
  );
}

/// 하루치 요약(최저/최고 기온 + 그 날의 시간별 목록).
class KmaDaySummary {
  KmaDaySummary({required this.date, required this.hourly});

  final DateTime date;
  final List<KmaHourly> hourly;

  double get minTempC =>
      hourly.map((h) => h.tempC).reduce((a, b) => a < b ? a : b);
  double get maxTempC =>
      hourly.map((h) => h.tempC).reduce((a, b) => a > b ? a : b);
  int get maxPopPercent =>
      hourly.map((h) => h.popPercent).reduce((a, b) => a > b ? a : b);

  /// 정오에 가장 가까운 시간값 — 그 날의 대표 하늘상태/강수형태 아이콘으로 쓴다.
  KmaHourly get representative {
    KmaHourly best = hourly.first;
    var bestDiff = (hourly.first.time.hour - 12).abs();
    for (final h in hourly) {
      final diff = (h.time.hour - 12).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = h;
      }
    }
    return best;
  }
}
