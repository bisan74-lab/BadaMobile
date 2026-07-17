import 'package:flutter/material.dart';

import 'country_borders_data.dart';
import 'map_projection.dart';

/// 지도 배경 위에 실제 국경·해안선(Natural Earth 데이터 기반)을 그린다.
class CoastlinePainter extends CustomPainter {
  CoastlinePainter({required this.projection});

  final MapProjection projection;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final polylines in countryBorders.values) {
      for (final points in polylines) {
        if (points.length < 2) continue;
        final start = projection.project(points.first.$1, points.first.$2);
        final path = Path()..moveTo(start.dx, start.dy);
        for (final p in points.skip(1)) {
          final o = projection.project(p.$1, p.$2);
          path.lineTo(o.dx, o.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CoastlinePainter oldDelegate) =>
      oldDelegate.projection.bounds != projection.bounds ||
      oldDelegate.projection.size != projection.size;
}
