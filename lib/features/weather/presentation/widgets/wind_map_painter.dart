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
  WindMapPainter({required this.particles, required this.color, super.repaint});

  final List<WindParticle> particles;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final p in particles) {
      final trail = p.trail;
      final n = trail.length;
      if (n < 2) continue;
      // 궤적을 잔상이 남는 흐름선으로 그린다: 꼬리(오래된 점)는 가늘고
      // 투명하게, 머리(최근 점)로 갈수록 진해진다. Windy 앱처럼 **가늘고
      // 은은하게**: 최대 굵기·최대 불투명도를 낮춰(굵기 0.25~0.8, 알파 최대
      // 0.5) 흰 선이 과하게 튀지 않고 촘촘히 깔리게 한다.
      for (var i = 1; i < n; i++) {
        final t = i / (n - 1); // 0(꼬리) ~ 1(머리)
        paint
          ..color = color.withValues(alpha: t * (0.3 + 0.7 * t) * 0.38)
          ..strokeWidth = 0.25 + t * 0.55;
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
