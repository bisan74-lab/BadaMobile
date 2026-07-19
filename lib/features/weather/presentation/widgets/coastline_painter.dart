import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'country_borders_data.dart';
import 'map_projection.dart';

/// 지도 배경 위에 실제 국경·해안선(Natural Earth 데이터 기반)을 그린다.
/// 윈디 지도처럼 **얇은 밝은 선 + 부드러운 그림자(글로우)**로 그려 입체감을 준다.
class CoastlinePainter extends CustomPainter {
  CoastlinePainter({required this.projection});

  final MapProjection projection;

  /// 지명 라벨과 동일한 보정값을 공유한다([kMapLonShift]).
  static const double _lonShift = kMapLonShift;

  @override
  void paint(Canvas canvas, Size size) {
    // 윈디 지도처럼 **얇고 검정에 가까운 선**으로 해안선을 그린다.
    // 어두운 바다 위에서도 경계가 읽히도록, 아주 옅은 밝은 헤일로(글로우)를
    // 살짝 깔고 그 위에 얇은 짙은 선을 얹는다.
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 1.4);
    final line = Paint()
      ..color = const Color(0xFF10161F).withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 수백 개 해안선·섬 폴리라인을 **하나의 Path**로 합쳐 한 번에 그린다
    // (폴리라인마다 drawPath를 부르면 블러 처리 비용이 커져 첫 프레임이
    // 크게 지연되고 화면이 잠깐 검게 보인다).
    final path = Path();
    for (final polylines in countryBorders.values) {
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
    }
    canvas.drawPath(path, halo);
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(covariant CoastlinePainter oldDelegate) =>
      oldDelegate.projection.bounds != projection.bounds ||
      oldDelegate.projection.size != projection.size;
}
