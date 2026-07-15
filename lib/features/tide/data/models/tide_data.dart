/// 만조/간조 이벤트.
class TideExtreme {
  const TideExtreme({
    required this.time,
    required this.heightCm,
    required this.isHigh,
  });

  final DateTime time;
  final double heightCm;

  /// true = 만조, false = 간조
  final bool isHigh;
}

/// 하루치 조석 정보.
class TideDay {
  const TideDay({
    required this.date,
    required this.locationId,
    required this.extremes,
    required this.hourlyHeightsCm,
  });

  final DateTime date;
  final String locationId;

  /// 시간순 만조/간조 목록 (보통 3~4개).
  final List<TideExtreme> extremes;

  /// 00시부터 24시까지 1시간 간격 조위 (25개, cm).
  final List<double> hourlyHeightsCm;

  /// [now] 이후 첫 만조/간조. 없으면 null.
  TideExtreme? nextExtremeAfter(DateTime now) {
    for (final e in extremes) {
      if (e.time.isAfter(now)) return e;
    }
    return null;
  }
}
