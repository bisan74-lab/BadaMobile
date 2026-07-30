import 'dart:math' as math;

/// 격자 기반 바람장(2D 벡터 필드).
///
/// u = 동서 성분(m/s, 동쪽이 +), v = 남북 성분(m/s, 북쪽이 +).
/// 값은 row-major(위도 증가 순 × 경도 증가 순)로 저장된다:
///   index = latIndex * lonSteps + lonIndex
class WindField {
  WindField({
    required this.time,
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
    required this.latSteps,
    required this.lonSteps,
    required this.u,
    required this.v,
    this.hasData = true,
    List<double>? lats,
    List<double>? lons,
  }) : lats = lats ?? _uniformAxis(minLat, maxLat, latSteps),
       lons = lons ?? _uniformAxis(minLon, maxLon, lonSteps);

  static List<double> _uniformAxis(double lo, double hi, int steps) {
    if (steps <= 1) return [lo];
    return [for (var i = 0; i < steps; i++) lo + i * (hi - lo) / (steps - 1)];
  }

  final DateTime time;
  final double minLat, maxLat, minLon, maxLon;

  /// 위도·경도 방향 격자점 개수.
  final int latSteps, lonSteps;

  /// 각 축의 실제 좌표값(오름차순). 서버가 적응형(비균일) 격자를 보내면
  /// 그 값을, 없으면(구버전 파일·앱 직접호출 폴백) 균일 간격을 채워 넣는다.
  /// 대한해협·서해·남해 연안처럼 바람이 촘촘히 변하는 핵심 해역은 간격이
  /// 더 좁고, 먼 바다·내륙 쪽은 더 넓다(같은 총 격자점 수 안에서 재배치).
  final List<double> lats;
  final List<double> lons;

  final List<double> u;
  final List<double> v;

  /// 이 시각이 모델의 실제 예보 범위 안인지. 서버 파일은 요청한 기간(예:
  /// 16일) 전체를 스텝으로 담지만, 모델(ecmwf_ifs025)의 실제 예보 한계를
  /// 넘는 시각은 값이 없어 0으로 채워 넣는다 — 그 상태를 "무풍"과 구분하려고
  /// 이 플래그를 둔다. false면 지도는 이 스텝을 회색(데이터 없음)으로 그린다.
  /// Open-Meteo 직접 호출(폴백)은 항상 실시간이라 기본값 true를 쓴다.
  final bool hasData;

  bool contains(double lat, double lon) =>
      lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon;

  /// 오름차순 [axis]에서 x를 감싸는 하한 인덱스(즉 axis[i] <= x <= axis[i+1]),
  /// 경계 밖이면 가장 가까운 끝 구간으로 clamp.
  static int _bracketLow(List<double> axis, double x) {
    final n = axis.length;
    if (n < 2) return 0;
    if (x <= axis[0]) return 0;
    if (x >= axis[n - 1]) return n - 2;
    var lo = 0, hi = n - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (axis[mid] <= x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// 비균일 축의 3점(xa,xb,xc)에 대한 [xb]에서의 유한차분 접선(비균일
  /// Catmull-Rom 스타일). 경계(xa==xb 또는 xc==xb)면 한쪽 시컨트로 대체한다.
  static double _tangent(
    double xa,
    double xb,
    double xc,
    double pa,
    double pb,
    double pc,
  ) {
    final hasLeft = xb - xa > 0;
    final hasRight = xc - xb > 0;
    if (!hasLeft && !hasRight) return 0;
    if (!hasLeft) return (pc - pb) / (xc - xb);
    if (!hasRight) return (pb - pa) / (xb - xa);
    final d1 = (pb - pa) / (xb - xa);
    final d2 = (pc - pb) / (xc - xb);
    return ((xc - xb) * d1 + (xb - xa) * d2) / (xc - xa);
  }

  /// (x1,p1)~(x2,p2) 사이 [x]에서의 3차 Hermite 보간(비균일 간격 지원).
  /// (x0,p0), (x3,p3)는 접선 추정용 이웃점(경계에선 x1==x0 또는 x3==x2로
  /// 넘겨 한쪽 시컨트로 자동 대체됨).
  static double _hermite(
    double x0,
    double x1,
    double x2,
    double x3,
    double p0,
    double p1,
    double p2,
    double p3,
    double x,
  ) {
    final h = x2 - x1;
    if (h <= 0) return p1;
    final t = ((x - x1) / h).clamp(0.0, 1.0);
    final m1 = _tangent(x0, x1, x2, p0, p1, p2);
    final m2 = _tangent(x1, x2, x3, p1, p2, p3);
    final t2 = t * t, t3 = t2 * t;
    final h00 = 2 * t3 - 3 * t2 + 1;
    final h10 = t3 - 2 * t2 + t;
    final h01 = -2 * t3 + 3 * t2;
    final h11 = t3 - t2;
    return h00 * p1 + h10 * h * m1 + h01 * p2 + h11 * h * m2;
  }

  /// (lat, lon)에서의 바람 벡터를 쌍3차(bicubic) 보간한다. 범위 밖이면 null.
  /// 격자가 비균일(적응형)이어도 각 축 실제 좌표([lats]/[lons])를 그대로
  /// 써서 보간하므로 정확하다. 인접 4×4점을 축별 3차 Hermite로 두 번(경도→
  /// 위도) 적용하는 방식이라, 예전 쌍선형보다 바람 줄기·소용돌이 경계가
  /// 부드럽고 세밀하게 드러난다(Windy 지도와의 텍스처 차이 개선).
  (double u, double v)? sample(double lat, double lon) {
    if (!contains(lat, lon)) return null;
    final i0 = _bracketLow(lats, lat);
    final j0 = _bracketLow(lons, lon);
    final i1 = (i0 + 1).clamp(0, latSteps - 1);
    final j1 = (j0 + 1).clamp(0, lonSteps - 1);
    final im1 = (i0 - 1).clamp(0, latSteps - 1);
    final ip1 = (i1 + 1).clamp(0, latSteps - 1);
    final jm1 = (j0 - 1).clamp(0, lonSteps - 1);
    final jp1 = (j1 + 1).clamp(0, lonSteps - 1);

    // 인접 4×4 격자점의 최소·최대. 쌍3차(Hermite)는 급격한 변화 근처에서
    // 과잉(overshoot)·링잉을 일으켜 실제엔 없는 곧은 띠(예: 적응형 격자 밀도
    // 전환 경계 ~위도 36°)나 홱 뒤틀린 풍향을 만든다. 보간값을 이 4×4 이웃의
    // 범위로 클램프하면 부드러움은 유지하면서 가짜 띠·이상 풍향만 억제한다.
    final iis = [im1, i0, i1, ip1];
    final jjs = [jm1, j0, j1, jp1];

    double interp(List<double> arr) {
      double rowAt(int i) {
        final base = i * lonSteps;
        return _hermite(
          lons[jm1],
          lons[j0],
          lons[j1],
          lons[jp1],
          arr[base + jm1],
          arr[base + j0],
          arr[base + j1],
          arr[base + jp1],
          lon,
        );
      }

      final raw = _hermite(
        lats[im1],
        lats[i0],
        lats[i1],
        lats[ip1],
        rowAt(im1),
        rowAt(i0),
        rowAt(i1),
        rowAt(ip1),
        lat,
      );
      var lo = arr[iis[0] * lonSteps + jjs[0]];
      var hi = lo;
      for (final i in iis) {
        final base = i * lonSteps;
        for (final j in jjs) {
          final v = arr[base + j];
          if (v < lo) lo = v;
          if (v > hi) hi = v;
        }
      }
      return raw.clamp(lo, hi);
    }

    return (interp(u), interp(v));
  }
}

/// 기상 관례 풍향(바람이 불어오는 방향, 도) + 속도(m/s)를
/// 흐름 방향 성분 (u=동서, v=남북)으로 변환한다.
(double u, double v) windToUv(double speedMs, double directionDeg) {
  final rad = directionDeg * math.pi / 180;
  return (-speedMs * math.sin(rad), -speedMs * math.cos(rad));
}

/// 특정 지점(정확한 위경도)의 시간별 바람 값.
///
/// 지도 격자(약 2° 간격)를 쌍선형 보간한 값이 아니라 그 좌표를 그대로 API에
/// 요청해 받은 원해상도 값이라, 윈디 앱의 지점 표시값과 직접 비교된다.
class PointWind {
  const PointWind({
    required this.time,
    required this.speedMs,
    required this.directionDeg,
  });

  final DateTime time;
  final double speedMs;

  /// 기상 관례 풍향(바람이 불어오는 방향, 도).
  final double directionDeg;
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
  /// [time]을 **지나온 마지막 스텝**(시각이 [time]보다 늦지 않은 것 중 마지막).
  ///
  /// "지금"을 가리킬 때는 [indexClosestTo]가 아니라 이걸 쓴다. 스텝이 3시간
  /// 간격이라 22:58에는 00시가 더 "가깝지만", 아직 오지 않은 시각을 지금이라고
  /// 표시하면 안 되기 때문이다. 모든 스텝이 [time]보다 미래면 첫 스텝을 쓴다.
  int indexAtOrBefore(DateTime time) {
    var idx = 0;
    for (var i = 0; i < hourly.length; i++) {
      if (hourly[i].time.isAfter(time)) break;
      idx = i;
    }
    return idx;
  }

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
