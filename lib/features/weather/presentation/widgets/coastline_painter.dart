import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'country_borders_data.dart';
import 'map_projection.dart';

/// 지도 배경 위에 실제 국경·해안선(Natural Earth 데이터 기반)을 그린다.
/// 윈디 지도처럼 **얇은 밝은 선 + 부드러운 그림자(글로우)**로 그려 입체감을 준다.
class CoastlinePainter extends CustomPainter {
  CoastlinePainter({required this.projection});

  final MapProjection projection;

  /// 내장 해안선 데이터가 실제 해안보다 약간 동쪽으로 치우쳐 있어(항구 점 대비),
  /// 경도를 서쪽으로 살짝 당겨 항구 위치와 맞춘다.
  static const double _lonShift = -0.5;

  @override
  void paint(Canvas canvas, Size size) {
    // 그림자(글로우): 넓고 어둡게 블러 처리해 밑에 깔고,
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 2);
    // 그 위에 얇고 밝은 선을 얹는다.
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final paths = <Path>[];
    for (final polylines in countryBorders.values) {
      for (final points in polylines) {
        if (points.length < 2) continue;
        final path = Path();
        final start = projection.project(
          points.first.$1,
          points.first.$2 + _lonShift,
        );
        path.moveTo(start.dx, start.dy);
        for (final p in points.skip(1)) {
          final o = projection.project(p.$1, p.$2 + _lonShift);
          path.lineTo(o.dx, o.dy);
        }
        paths.add(path);
      }
    }
    for (final path in paths) {
      canvas.drawPath(path, shadow);
    }
    for (final path in paths) {
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(covariant CoastlinePainter oldDelegate) =>
      oldDelegate.projection.bounds != projection.bounds ||
      oldDelegate.projection.size != projection.size;
}
