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
