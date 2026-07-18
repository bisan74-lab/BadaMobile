import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 라이선스 걱정 없는 "직접 그린" 바다 일러스트 배경.
/// 하늘 그라디언트 + 은은한 해/달 + 잔잔한 파도 레이어를 코드로 그린다.
/// 물때 타임라인·설정 등 여러 화면의 편안한 배경으로 재사용한다.
class SeaBackdrop extends StatelessWidget {
  const SeaBackdrop({super.key, this.sunset = false, this.opacity = 1});

  /// true면 노을(주황) 톤, false면 낮 바다(파랑) 톤.
  final bool sunset;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: CustomPaint(painter: _SeaBackdropPainter(sunset: sunset)),
    );
  }
}

class _SeaBackdropPainter extends CustomPainter {
  _SeaBackdropPainter({required this.sunset});

  final bool sunset;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final horizon = h * 0.52;

    // 하늘 그라디언트.
    final skyColors = sunset
        ? const [Color(0xFF3A2A4D), Color(0xFF7E3B4E), Color(0xFFC9683E)]
        : const [Color(0xFF123C5E), Color(0xFF1E5C8A), Color(0xFF3E86B5)];
    final sky = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: skyColors,
      ).createShader(Rect.fromLTWH(0, 0, w, horizon));
    canvas.drawRect(Rect.fromLTWH(0, 0, w, horizon), sky);

    // 은은한 해/달 + 빛무리.
    final sunCenter = Offset(w * 0.72, horizon * 0.55);
    final sunColor = sunset ? const Color(0xFFFFD9A0) : const Color(0xFFFDF5E6);
    canvas.drawCircle(
      sunCenter,
      horizon * 0.7,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                sunColor.withValues(alpha: 0.5),
                sunColor.withValues(alpha: 0),
              ],
            ).createShader(
              Rect.fromCircle(center: sunCenter, radius: horizon * 0.7),
            ),
    );
    canvas.drawCircle(
      sunCenter,
      horizon * 0.18,
      Paint()..color = sunColor.withValues(alpha: 0.85),
    );

    // 바다.
    final seaColors = sunset
        ? const [Color(0xFF6B3B54), Color(0xFF2E2140)]
        : const [Color(0xFF0E3E63), Color(0xFF082238)];
    final sea = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: seaColors,
      ).createShader(Rect.fromLTWH(0, horizon, w, h - horizon));
    canvas.drawRect(Rect.fromLTWH(0, horizon, w, h - horizon), sea);

    // 해가 바다에 반사되는 빛줄기.
    final reflect = Paint()..color = sunColor.withValues(alpha: 0.12);
    canvas.drawPath(
      Path()
        ..moveTo(sunCenter.dx - 10, horizon)
        ..lineTo(sunCenter.dx + 10, horizon)
        ..lineTo(sunCenter.dx + w * 0.12, h)
        ..lineTo(sunCenter.dx - w * 0.12, h)
        ..close(),
      reflect,
    );

    // 잔잔한 파도 레이어(사인 곡선 3겹).
    final waveColor = sunset
        ? const Color(0xFFF0B080)
        : const Color(0xFFAFD4EC);
    for (var layer = 0; layer < 3; layer++) {
      final baseY = horizon + (h - horizon) * (0.25 + layer * 0.3);
      final amp = 5.0 + layer * 3;
      final path = Path()..moveTo(0, baseY);
      for (var x = 0.0; x <= w; x += 6) {
        final y =
            baseY + amp * math.sin((x / w) * math.pi * (3 + layer) + layer);
        path.lineTo(x, y);
      }
      path
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(
        path,
        Paint()..color = waveColor.withValues(alpha: 0.06 + layer * 0.03),
      );
    }
  }

  @override
  bool shouldRepaint(_SeaBackdropPainter oldDelegate) =>
      oldDelegate.sunset != sunset;
}
