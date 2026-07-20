import 'dart:math' as math;

/// 격자 기반 바람장(2D 벡터 필드).
///
/// u = 동서 성분(m/s, 동쪽이 +), v = 남북 성분(m/s, 북쪽이 +).
/// 값은 row-major(위도 증가 순 × 경도 증가 순)로 저장된다:
///   index = latIndex * lonSteps + lonIndex
class WindField {
  const WindField({
    required this.time,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    required this.latSteps,
    required this.lonSteps,
    required this.u,
    required this.v,
  });

  final DateTime time;
  final double minLat, maxLat, minLon, maxLon;

  /// 위도·경도 방향 격자점 개수.
  final int latSteps, lonSteps;

  final List<double> u;
  final List<double> v;

  double get latStep => (maxLat - minLat) / (latSteps - 1);
  double get lonStep => (maxLon - minLon) / (lonSteps - 1);

  bool contains(double lat, double lon) =>
      lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;

  /// (lat, lon)에서의 바람 벡터를 쌍선형 보간한다. 범위 밖이면 null.
  (double u, double v)? sample(double lat, double lon) {
    if (!contains(lat, lon)) return null;
    final fi = (lat - minLat) / latStep;
    final fj = (lon - minLon) / lonStep;
    final i0 = fi.floor().clamp(0, latSteps - 1);
    final j0 = fj.floor().clamp(0, lonSteps - 1);
    final i1 = (i0 + 1).clamp(0, latSteps - 1);
    final j1 = (j0 + 1).clamp(0, lonSteps - 1);
    final ti = (fi - i0).clamp(0.0, 1.0);
    final tj = (fj - j0).clamp(0.0, 1.0);

    double at(List<double> arr, int i, int j) => arr[i * lonSteps + j];
    double lerp(double a, double b, double t) => a + (b - a) * t;

    final uu = lerp(
      lerp(at(u, i0, j0), at(u, i0, j1), tj),
      lerp(at(u, i1, j0), at(u, i1, j1), tj),
      ti,
    );
    final vv = lerp(
      lerp(at(v, i0, j0), at(v, i0, j1), tj),
      lerp(at(v, i1, j0), at(v, i1, j1), tj),
      ti,
    );
    return (uu, vv);
  }
}

/// 기상 관례 풍향(바람이 불어오는 방향, 도) + 속도(m/s)를
/// 흐름 방향 성분 (u=동서, v=남북)으로 변환한다.
(double u, double v) windToUv(double speedMs, double directionDeg) {
  final rad = directionDeg * math.pi / 180;
  return (-speedMs * math.sin(rad), -speedMs * math.cos(rad));
}

/// 같은 격자 지리(bbox·해상도)에 대해 시간대별 [WindField] 스냅샷을 모은 것.
/// 윈디 스타일 시간 스크러버(time slider)에 쓰인다.
class WindFieldSeries {
  const WindFieldSeries({required this.hourly});

  /// 시간순 스냅샷(보통 1시간 간격).
  final List<WindField> hourly;

  /// [offset]시간째 스냅샷. 범위를 벗어나면 가장 가까운 끝으로 고정한다.
  WindField at(int offset) => hourly[offset.clamp(0, hourly.length - 1)];

  /// [time]과 가장 가까운 스냅샷의 인덱스(지도 시각을 예보 슬라이더와 맞출 때).
  int indexClosestTo(DateTime time) {
    var best = 0;
    Duration bestDiff = const Duration(days: 9999);
    for (var i = 0; i < hourly.length; i++) {
      final d = hourly[i].time.difference(time).abs();
      if (d < bestDiff) {
        bestDiff = d;
        best = i;
      }
    }
    return best;
  }

  int get length => hourly.length;
}
