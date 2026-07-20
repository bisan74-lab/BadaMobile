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
      // 투명하게, 머리(최근 점)로 갈수록 진해지고 살짝 굵어져 Windy 앱의
      // 올챙이(길쭉한 흐름선)처럼 보이게 한다. 페이드를 t²(빠른 소멸)에서
      // 완만하게 바꿔 꼬리가 더 길게 살아남도록 하고(잔상↑), 머리는 조금 더
      // 밝고 굵게 해 진행 방향이 또렷하게 보이게 한다.
      for (var i = 1; i < n; i++) {
        final t = i / (n - 1); // 0(꼬리) ~ 1(머리)
        paint
          ..color = color.withValues(alpha: t * (0.35 + 0.65 * t) * 0.72)
          ..strokeWidth = 0.45 + t * 1.15;
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
