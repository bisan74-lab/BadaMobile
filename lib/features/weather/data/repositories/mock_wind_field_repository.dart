import 'dart:math' as math;

import '../../../../core/utils/kst.dart';
import '../models/wind_field.dart';
import 'open_meteo_wind_field_repository.dart';
import 'wind_field_repository.dart';

/// 합성 바람장(네트워크 실패 시 폴백 전용). 실제 Open-Meteo 데이터가 아니라
/// 근사값이므로 Windy와 값이 정확히 맞지는 않지만, 여러 개의 이동성 기압계를
/// 겹쳐 **공간적으로 강·약이 또렷이 갈리는**(약 1~16 m/s) 바람장을 만들어
/// 지도가 한 가지 색으로 뭉개지지 않고 색 구분이 보이게 한다. 시간에 따라
/// 기압계가 이동해 스크러버로 시간을 바꾸면 패턴도 달라진다.
/// 격자 범위·해상도는 [OpenMeteoWindFieldRepository]와 동일하게 맞춘다.
class MockWindFieldRepository implements WindFieldRepository {
  @override
  Future<WindField> fetchField() async => _buildField(nowKst());

  @override
  Future<WindFieldSeries> fetchSeries({int hours = 48}) async {
    // 실제 API처럼 정시(서울 시간) 눈금으로 맞춰, 시간 슬라이더의 "지금"
    // 배지·상대 표시가 목업에서도 어긋나지 않게 한다.
    final now = nowKst();
    final start = DateTime(now.year, now.month, now.day, now.hour);
    return WindFieldSeries(
      hourly: List.generate(
        hours,
        (h) => _buildField(start.add(Duration(hours: h))),
      ),
    );
  }

  @override
  Future<List<PointWind>> fetchPointSeries(
    double lat,
    double lon, {
    int days = 16,
  }) async {
    final series = await fetchSeries(hours: days * 24);
    return [
      for (final f in series.hourly)
        if (f.sample(lat, lon) case (final double u, final double v))
          PointWind(
            time: f.time,
            speedMs: math.sqrt(u * u + v * v),
            directionDeg: (math.atan2(-u, -v) * 180 / math.pi + 360) % 360,
          ),
    ];
  }

  WindField _buildField(DateTime at) {
    const minLat = OpenMeteoWindFieldRepository.minLat;
    const maxLat = OpenMeteoWindFieldRepository.maxLat;
    const minLon = OpenMeteoWindFieldRepository.minLon;
    const maxLon = OpenMeteoWindFieldRepository.maxLon;
    const latSteps = OpenMeteoWindFieldRepository.latSteps;
    const lonSteps = OpenMeteoWindFieldRepository.lonSteps;

    final latStep = (maxLat - minLat) / (latSteps - 1);
    final lonStep = (maxLon - minLon) / (lonSteps - 1);
    final u = <double>[];
    final v = <double>[];
    // 시간에 따라 기압계가 서서히 이동하도록 하는 위상(하루 주기 + 누적 진행).
    final ph =
        (at.hour + at.minute / 60) * 0.26 + at.millisecondsSinceEpoch / 3.6e9;

    for (var i = 0; i < latSteps; i++) {
      final lat = minLat + i * latStep;
      for (var j = 0; j < lonSteps; j++) {
        final lon = minLon + j * lonStep;
        // 서로 다른 파장의 성분을 겹쳐 강풍대·약풍대가 공간적으로 갈리게 한다.
        final speed =
            (6.0 +
                    5.0 * math.sin(lat * 0.55 + ph) +
                    3.5 * math.cos(lon * 0.5 - ph * 0.8) +
                    2.5 * math.sin((lat + lon) * 0.35 + ph * 1.4))
                .clamp(0.5, 20.0);
        final dirDeg =
            200 + 55 * math.sin(lon * 0.4 + ph) + 30 * math.cos(lat * 0.5 - ph);
        final rad = dirDeg * math.pi / 180;
        var uu = -speed * math.sin(rad);
        var vv = -speed * math.cos(rad);
        // 중심부(한반도 중부) 부근 소용돌이 성분을 더해 곡선 흐름을 만든다.
        final dx = lon - 127.5, dy = lat - 36.0;
        final r2 = dx * dx + dy * dy + 0.3;
        uu += -dy / r2 * 1.5;
        vv += dx / r2 * 1.5;
        u.add(uu);
        v.add(vv);
      }
    }

    return WindField(
      time: at,
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
      latSteps: latSteps,
      lonSteps: lonSteps,
      u: u,
      v: v,
    );
  }
}
