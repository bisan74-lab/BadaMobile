import 'package:flutter/material.dart';

/// 한반도 해안선 간이 근사치(측량 데이터 아님, 지도 위 위치 참고용 시각 요소).
/// 서해안 → 남해안 → 동해안 순서로 좌표를 이어 그린다.
const List<(double lat, double lon)> _koreaCoastline = [
  (38.62, 125.20),
  (37.95, 124.70),
  (37.45, 126.40),
  (36.95, 126.50),
  (36.40, 126.50),
  (35.98, 126.70),
  (35.40, 126.40),
  (34.80, 126.40),
  (34.50, 126.30),
  (34.60, 127.10),
  (34.70, 127.50),
  (34.90, 128.00),
  (35.10, 128.60),
  (35.10, 129.05),
  (35.50, 129.40),
  (36.00, 129.40),
  (36.50, 129.40),
  (37.40, 129.20),
  (38.20, 128.60),
  (38.60, 128.30),
];

/// 제주도 윤곽 근사치.
const List<(double lat, double lon)> _jejuOutline = [
  (33.55, 126.30),
  (33.45, 126.20),
  (33.24, 126.30),
  (33.20, 126.55),
  (33.24, 126.85),
  (33.45, 126.90),
  (33.55, 126.70),
  (33.55, 126.30),
];

/// 지도 배경 위에 육지·바다 경계선을 그려 위치 감을 준다.
class CoastlinePainter extends CustomPainter {
  CoastlinePainter({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  final double minLat, maxLat, minLon, maxLon;

  Offset _project(double lat, double lon, Size size) => Offset(
    (lon - minLon) / (maxLon - minLon) * size.width,
    (1 - (lat - minLat) / (maxLat - minLat)) * size.height,
  );

  void _drawLine(
    Canvas canvas,
    Size size,
    List<(double, double)> points,
    Paint paint,
  ) {
    if (points.length < 2) return;
    final start = _project(points.first.$1, points.first.$2, size);
    final path = Path()..moveTo(start.dx, start.dy);
    for (final p in points.skip(1)) {
      final o = _project(p.$1, p.$2, size);
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    _drawLine(canvas, size, _koreaCoastline, paint);
    _drawLine(canvas, size, _jejuOutline, paint);
  }

  @override
  bool shouldRepaint(covariant CoastlinePainter oldDelegate) => false;
}
