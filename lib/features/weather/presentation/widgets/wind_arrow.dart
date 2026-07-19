import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 풍향 화살표. [directionDeg]는 바람이 불어오는 방향(기상 관례)이므로
/// 화살표는 바람이 불어가는 쪽(+180도)을 가리키게 회전한다.
class WindArrow extends StatelessWidget {
  const WindArrow({
    super.key,
    required this.directionDeg,
    this.size = 20,
    this.color,
  });

  final double directionDeg;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      // Icons.navigation은 위(북)를 가리키므로 불어가는 방향으로 회전.
      angle: (directionDeg + 180) * math.pi / 180,
      child: Icon(Icons.navigation, size: size, color: color),
    );
  }
}

/// 표 안에 넣는 작은 **길쭉한 화살촉** 모양 풍향(또는 파향) 아이콘.
/// [directionDeg]는 밀려오는(불어오는) 방향이므로 화살촉은 진행 방향
/// (+180도)을 가리키게 그린다. Windy의 방향 화살표와 같은 느낌.
class DirectionArrow extends StatelessWidget {
  const DirectionArrow({
    super.key,
    required this.directionDeg,
    this.size = 12,
    this.color = Colors.white,
  });

  final double directionDeg;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: (directionDeg + 180) * math.pi / 180,
      child: CustomPaint(
        size: Size(size, size),
        painter: _ArrowheadPainter(color),
      ),
    );
  }
}

class _ArrowheadPainter extends CustomPainter {
  _ArrowheadPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // 위(북)를 향하는 길쭉한 화살촉: 뾰족한 머리 + 짧은 꼬리.
    final path = Path()
      ..moveTo(w * 0.5, 0) // 머리(맨 위)
      ..lineTo(w * 0.85, h * 0.9) // 오른쪽 아래
      ..lineTo(w * 0.5, h * 0.66) // 안쪽 홈
      ..lineTo(w * 0.15, h * 0.9) // 왼쪽 아래
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_ArrowheadPainter old) => old.color != color;
}
