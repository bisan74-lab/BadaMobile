import 'package:flutter/material.dart';

/// 바람장을 따라 흐르는 파티클 하나. 위치는 지리 좌표(lat/lon),
/// 궤적(trail)은 정규화 캔버스 좌표([0,1] × [0,1])로 보관한다.
class WindParticle {
  WindParticle({
    required this.lat,
    required this.lon,
    required this.age,
    required this.trail,
  });

  double lat;
  double lon;
  double age;
  final List<Offset> trail;
}

/// [particles]의 궤적을 오래된 구간일수록 흐리게 그린다 (윈디 스타일 흐름선).
class WindMapPainter extends CustomPainter {
  WindMapPainter({required this.particles, required this.color});

  final List<WindParticle> particles;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (final p in particles) {
      final trail = p.trail;
      if (trail.length < 2) continue;
      for (var i = 1; i < trail.length; i++) {
        final t = i / trail.length;
        paint.color = color.withValues(alpha: t * 0.85);
        canvas.drawLine(
          Offset(trail[i - 1].dx * size.width, trail[i - 1].dy * size.height),
          Offset(trail[i].dx * size.width, trail[i].dy * size.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant WindMapPainter oldDelegate) => true;
}
