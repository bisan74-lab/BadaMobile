import 'dart:typed_data';
import 'dart:ui' show PointMode;

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
///
/// **성능**: 세그먼트마다 `drawLine`을 부르면 콜 수가 파티클수×궤적수(수만~
/// 십만)가 되어 프레임이 무너지고(그러면 틱의 dt가 커져 위치 갱신이 아예
/// 스킵돼 바람이 멈춰 보인다), 파티클을 늘릴 수도 없다. 그래서 궤적 위치
/// (꼬리→머리)를 [_buckets]단계로 나눠 **단계마다 `drawRawPoints`(선분 모드)
/// 한 번**으로 그린다 — 파티클이 몇 개든 캔버스 콜은 상수(6번)로 유지된다.
class WindMapPainter extends CustomPainter {
  WindMapPainter({required this.particles, required this.color, super.repaint});

  final List<WindParticle> particles;
  final Color color;

  /// 잔상 페이드를 나누는 단계 수(꼬리=흐림·가늘음 → 머리=진함·굵음).
  static const _buckets = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    // 단계별 선분 끝점을 모은다: [x0,y0,x1,y1, ...] (선분 하나당 점 2개).
    final seg = List.generate(_buckets, (_) => <double>[], growable: false);
    for (final p in particles) {
      final trail = p.trail;
      final n = trail.length;
      if (n < 2) continue;
      for (var i = 1; i < n; i++) {
        final t = i / (n - 1); // 0(꼬리) ~ 1(머리)
        var b = (t * _buckets).floor();
        if (b >= _buckets) b = _buckets - 1;
        final s = seg[b];
        s.add(trail[i - 1].dx * w);
        s.add(trail[i - 1].dy * h);
        s.add(trail[i].dx * w);
        s.add(trail[i].dy * h);
      }
    }
    // 가늘고 은은하되, 이동이 눈에 띄도록 머리 쪽을 조금 더 진하고 굵게:
    // 굵기 0.3~0.95, 알파 최대 ~0.5(이전 0.38에서 상향).
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var b = 0; b < _buckets; b++) {
      final s = seg[b];
      if (s.isEmpty) continue;
      final t = (b + 0.5) / _buckets;
      paint
        ..color = color.withValues(alpha: t * (0.3 + 0.7 * t) * 0.5)
        ..strokeWidth = 0.3 + t * 0.65;
      canvas.drawRawPoints(PointMode.lines, Float32List.fromList(s), paint);
    }
  }

  @override
  bool shouldRepaint(covariant WindMapPainter oldDelegate) => true;
}
