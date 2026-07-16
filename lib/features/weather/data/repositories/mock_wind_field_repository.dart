import 'dart:math' as math;

import '../models/wind_field.dart';
import 'open_meteo_wind_field_repository.dart';
import 'wind_field_repository.dart';

/// 합성 바람장. 남서풍 베이스 흐름에 중심부 소용돌이 성분을 더해
/// 네트워크 없이도 자연스러운 곡선 흐름을 만든다.
/// 격자 범위·해상도는 [OpenMeteoWindFieldRepository]와 동일하게 맞춰
/// 실데이터 실패 시 폴백해도 지도 화면이 동일하게 동작한다.
class MockWindFieldRepository implements WindFieldRepository {
  @override
  Future<WindField> fetchField() async => _buildField(DateTime.now());

  @override
  Future<WindFieldSeries> fetchSeries({int hours = 48}) async {
    final start = DateTime.now();
    return WindFieldSeries(
      hourly: List.generate(
        hours,
        (h) => _buildField(start.add(Duration(hours: h))),
      ),
    );
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
    final seed = at.hour + at.minute / 60;

    for (var i = 0; i < latSteps; i++) {
      final lat = minLat + i * latStep;
      for (var j = 0; j < lonSteps; j++) {
        final lon = minLon + j * lonStep;
        final baseSpeed = 4.5 + 2.0 * math.sin(seed + lat / 3);
        final baseDirRad = (200 + 20 * math.sin(lon + seed)) * math.pi / 180;
        var uu = -baseSpeed * math.sin(baseDirRad);
        var vv = -baseSpeed * math.cos(baseDirRad);
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
