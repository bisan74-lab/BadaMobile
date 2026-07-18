import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/weather_code.dart';

/// 라이선스 걱정 없는 "직접 그린" 날씨 아이콘(구름·비·해·눈·번개 등).
/// [WeatherIconKind]에 따라 `CustomPainter`로 그린다. 외부 이미지·폰트 없음.
class WeatherIcon extends StatelessWidget {
  const WeatherIcon({
    super.key,
    required this.code,
    this.size = 40,
    this.night = false,
  });

  /// WMO 날씨 코드(내부에서 아이콘 종류로 변환).
  final int code;
  final double size;
  final bool night;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _WeatherIconPainter(kind: wmoIcon(code), night: night),
      ),
    );
  }
}

class _WeatherIconPainter extends CustomPainter {
  _WeatherIconPainter({required this.kind, required this.night});

  final WeatherIconKind kind;
  final bool night;

  static const _sun = Color(0xFFFFC93C);
  static const _moon = Color(0xFFE7ECF3);
  static const _cloud = Color(0xFFB9C6D3);
  static const _cloudDark = Color(0xFF8A99A8);
  static const _rain = Color(0xFF4A90D9);
  static const _snow = Color(0xFFE8F3FF);
  static const _bolt = Color(0xFFFFD23F);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final unit = math.min(w, h);

    switch (kind) {
      case WeatherIconKind.clear:
        _drawSunOrMoon(canvas, Offset(w * 0.5, h * 0.5), unit * 0.26);
      case WeatherIconKind.partlyCloudy:
        _drawSunOrMoon(canvas, Offset(w * 0.36, h * 0.36), unit * 0.2);
        _drawCloud(canvas, size, dy: 0.12, color: _cloud);
      case WeatherIconKind.cloudy:
        _drawCloud(canvas, size, dy: 0.02, color: _cloudDark);
        _drawCloud(canvas, size, dy: -0.06, color: _cloud);
      case WeatherIconKind.fog:
        _drawCloud(canvas, size, dy: -0.1, color: _cloud);
        _drawLines(canvas, size, count: 3, color: _cloudDark, slant: 0);
      case WeatherIconKind.drizzle:
        _drawCloud(canvas, size, dy: -0.12, color: _cloud);
        _drawDrops(canvas, size, count: 3, small: true);
      case WeatherIconKind.rain:
        _drawCloud(canvas, size, dy: -0.12, color: _cloudDark);
        _drawDrops(canvas, size, count: 4, small: false);
      case WeatherIconKind.snow:
        _drawCloud(canvas, size, dy: -0.12, color: _cloud);
        _drawFlakes(canvas, size, count: 3);
      case WeatherIconKind.sleet:
        _drawCloud(canvas, size, dy: -0.12, color: _cloud);
        _drawDrops(canvas, size, count: 2, small: true);
        _drawFlakes(canvas, size, count: 1);
      case WeatherIconKind.thunder:
        _drawCloud(canvas, size, dy: -0.12, color: _cloudDark);
        _drawBolt(canvas, size);
    }
  }

  void _drawSunOrMoon(Canvas canvas, Offset c, double r) {
    if (night) {
      // 초승달: 큰 원 - 살짝 겹친 원으로 파낸다.
      final paint = Paint()..color = _moon;
      final path = Path()..addOval(Rect.fromCircle(center: c, radius: r));
      final cut = Path()
        ..addOval(
          Rect.fromCircle(center: c.translate(r * 0.5, -r * 0.35), radius: r),
        );
      canvas.drawPath(Path.combine(PathOperation.difference, path, cut), paint);
    } else {
      final paint = Paint()..color = _sun;
      // 광선.
      final ray = Paint()
        ..color = _sun
        ..strokeWidth = r * 0.22
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 8; i++) {
        final a = i * math.pi / 4;
        final p1 = c + Offset(math.cos(a), math.sin(a)) * r * 1.35;
        final p2 = c + Offset(math.cos(a), math.sin(a)) * r * 1.75;
        canvas.drawLine(p1, p2, ray);
      }
      canvas.drawCircle(c, r, paint);
    }
  }

  void _drawCloud(
    Canvas canvas,
    Size size, {
    required double dy,
    required Color color,
  }) {
    final w = size.width;
    final h = size.height;
    final cy = h * (0.5 + dy);
    final path = Path();
    final base = Rect.fromLTWH(w * 0.16, cy, w * 0.68, h * 0.26);
    path.addRRect(RRect.fromRectAndRadius(base, Radius.circular(h * 0.13)));
    path.addOval(
      Rect.fromCircle(center: Offset(w * 0.36, cy), radius: h * 0.15),
    );
    path.addOval(
      Rect.fromCircle(
        center: Offset(w * 0.56, cy - h * 0.05),
        radius: h * 0.19,
      ),
    );
    path.addOval(
      Rect.fromCircle(center: Offset(w * 0.72, cy), radius: h * 0.14),
    );
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawDrops(
    Canvas canvas,
    Size size, {
    required int count,
    required bool small,
  }) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = _rain
      ..strokeWidth = h * (small ? 0.03 : 0.045)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final x = w * (0.32 + i * 0.15);
      final y = h * 0.7;
      canvas.drawLine(
        Offset(x, y),
        Offset(x - w * 0.05, y + h * (small ? 0.12 : 0.18)),
        paint,
      );
    }
  }

  void _drawFlakes(Canvas canvas, Size size, {required int count}) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = _snow
      ..strokeWidth = h * 0.03
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final c = Offset(w * (0.4 + i * 0.14), h * 0.78);
      final r = h * 0.06;
      for (var a = 0; a < 3; a++) {
        final ang = a * math.pi / 3;
        canvas.drawLine(
          c + Offset(math.cos(ang), math.sin(ang)) * r,
          c - Offset(math.cos(ang), math.sin(ang)) * r,
          paint,
        );
      }
    }
  }

  void _drawLines(
    Canvas canvas,
    Size size, {
    required int count,
    required Color color,
    required double slant,
  }) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = color
      ..strokeWidth = h * 0.04
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final y = h * (0.66 + i * 0.11);
      canvas.drawLine(Offset(w * 0.24, y), Offset(w * 0.76, y), paint);
    }
  }

  void _drawBolt(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.52, h * 0.62)
      ..lineTo(w * 0.4, h * 0.82)
      ..lineTo(w * 0.5, h * 0.82)
      ..lineTo(w * 0.42, h * 0.98)
      ..lineTo(w * 0.62, h * 0.74)
      ..lineTo(w * 0.5, h * 0.74)
      ..close();
    canvas.drawPath(path, Paint()..color = _bolt);
  }

  @override
  bool shouldRepaint(_WeatherIconPainter old) =>
      old.kind != kind || old.night != night;
}
