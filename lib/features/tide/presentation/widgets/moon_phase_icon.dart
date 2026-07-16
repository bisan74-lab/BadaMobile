import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/utils/mul_ttae.dart';

/// [date]의 근사 월령으로 달의 위상(삭~보름~삭)을 작은 원으로 그린다.
/// 장식용 지표이며 물때 배지의 보조 정보로 쓴다.
class MoonPhaseIcon extends StatelessWidget {
  const MoonPhaseIcon({super.key, required this.date, this.size = 32});

  final DateTime date;
  final double size;

  @override
  Widget build(BuildContext context) {
    final phase = lunarAgeDays(date) / synodicMonthDays; // 0=삭, 0.5=보름
    return CustomPaint(
      size: Size.square(size),
      painter: _MoonPhasePainter(phase: phase),
    );
  }
}

class _MoonPhasePainter extends CustomPainter {
  _MoonPhasePainter({required this.phase});

  final double phase;

  static const _dark = Color(0xFF17293D);
  static const _light = Color(0xFFF4E9CE);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final center = Offset(r, r);
    canvas.drawCircle(center, r, Paint()..color = _dark);

    final theta = 2 * math.pi * phase;
    final rx = r * math.cos(theta);
    final waxing = phase < 0.5;

    final path = Path()
      ..moveTo(center.dx, center.dy - r)
      ..arcToPoint(
        Offset(center.dx, center.dy + r),
        radius: Radius.circular(r),
        clockwise: waxing,
      )
      ..arcToPoint(
        Offset(center.dx, center.dy - r),
        radius: Radius.elliptical(rx.abs(), r),
        clockwise: waxing ? rx <= 0 : rx > 0,
      );
    canvas.drawPath(path, Paint()..color = _light);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _MoonPhasePainter oldDelegate) =>
      oldDelegate.phase != phase;
}
