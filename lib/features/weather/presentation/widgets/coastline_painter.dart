import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'country_borders_data.dart';
import 'map_projection.dart';

/// 지도 배경 위에 실제 국경·해안선(Natural Earth 데이터 기반)을 그린다.
/// 윈디 지도처럼 **얇은 밝은 선 + 부드러운 그림자(글로우)**로 그려 입체감을 준다.
class CoastlinePainter extends CustomPainter {
  CoastlinePainter({required this.projection, this.scale = 1.0});

  final MapProjection projection;

  /// 현재 지도 확대 배율. 이 레이어는 `InteractiveViewer`가 통째로 확대하므로,
  /// 선 두께를 1/scale로 그려 화면상 두께를 확대와 무관하게 얇게 유지한다
  /// (안 그러면 확대할수록 해안선이 굵어져 보기 안 좋다).
  final double scale;

  /// 지명 라벨과 동일한 보정값을 공유한다([kMapLonShift]).
  static const double _lonShift = kMapLonShift;

  /// 한 레이어(키)의 모든 폴리라인을 하나의 Path로 합친다.
  Path _pathFor(String key) {
    final path = Path();
    final polylines = countryBorders[key];
    if (polylines == null) return path;
    for (final points in polylines) {
      if (points.length < 2) continue;
      final start = projection.project(
        points.first.$1,
        points.first.$2 + _lonShift,
      );
      path.moveTo(start.dx, start.dy);
      for (final p in points.skip(1)) {
        final o = projection.project(p.$1, p.$2 + _lonShift);
        path.lineTo(o.dx, o.dy);
      }
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = scale <= 0 ? 1.0 : scale;

    // 확대할수록(행정경계·하천 등) 지형의 디테일한 선이 드러나게 한다.
    // 각 레이어는 하나의 Path로 합쳐 한 번에 그려 성능을 유지한다.

    // 하천(강): 조금 확대하면 옅은 청색 선으로.
    if (s >= 2.2) {
      canvas.drawPath(
        _pathFor('강'),
        Paint()
          ..color = const Color(0xFF6FA8C7).withValues(alpha: 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.55 / s
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }
    // 행정경계(주·성): 살짝만 확대해도 아주 옅은 얇은 선으로 드러난다.
    if (s >= 1.8) {
      canvas.drawPath(
        _pathFor('행정'),
        Paint()
          ..color = const Color(0xFF2A3543).withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.42 / s
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    // 해안선·국경: 항상. 윈디처럼 얇고 검정에 가까운 선 + 옅은 헤일로.
    final coast = _pathFor('해안선');
    final border = _pathFor('국경');
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 / s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 1.2 / s);
    // 바다-육지 경계선은 더 진하고 살짝 굵게 그려 또렷하게 보이도록 한다.
    final coastLine = Paint()
      ..color = const Color(0xFF080C12).withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.85 / s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final borderLine = Paint()
      ..color = const Color(0xFF1B2430).withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5 / s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(coast, halo);
    canvas.drawPath(border, borderLine);
    canvas.drawPath(coast, coastLine);
  }

  @override
  bool shouldRepaint(covariant CoastlinePainter oldDelegate) =>
      oldDelegate.projection.bounds != projection.bounds ||
      oldDelegate.projection.size != projection.size ||
      oldDelegate.scale != scale;
}
