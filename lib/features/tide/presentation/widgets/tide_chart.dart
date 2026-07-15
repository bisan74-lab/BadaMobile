import 'package:flutter/material.dart';

/// 하루 조위 곡선 차트 (CustomPaint).
class TideChart extends StatelessWidget {
  const TideChart({super.key, required this.hourlyHeightsCm, this.now});

  /// 00시~24시 1시간 간격 조위 (25개).
  final List<double> hourlyHeightsCm;

  /// 현재 시각 표시선 (차트 날짜와 같은 날일 때만 전달).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 2.2,
      child: CustomPaint(
        painter: _TideChartPainter(
          heights: hourlyHeightsCm,
          lineColor: scheme.primary,
          fillColor: scheme.primary.withValues(alpha: 0.15),
          gridColor: scheme.outlineVariant,
          nowColor: scheme.error,
          labelStyle: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          nowFractionOfDay: now == null
              ? null
              : (now!.hour * 60 + now!.minute) / (24 * 60),
        ),
      ),
    );
  }
}

class _TideChartPainter extends CustomPainter {
  _TideChartPainter({
    required this.heights,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
    required this.nowColor,
    required this.labelStyle,
    required this.nowFractionOfDay,
  });

  final List<double> heights;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;
  final Color nowColor;
  final TextStyle? labelStyle;
  final double? nowFractionOfDay;

  @override
  void paint(Canvas canvas, Size size) {
    if (heights.length < 2) return;

    const bottomPad = 18.0;
    final chartHeight = size.height - bottomPad;
    final minH = heights.reduce((a, b) => a < b ? a : b);
    final maxH = heights.reduce((a, b) => a > b ? a : b);
    final range = (maxH - minH).abs() < 1 ? 1.0 : maxH - minH;

    Offset pointAt(int i) {
      final x = size.width * i / (heights.length - 1);
      final normalized = (heights[i] - minH) / range;
      final y = chartHeight * (1 - normalized) * 0.85 + chartHeight * 0.075;
      return Offset(x, y);
    }

    // 6시간 간격 세로 그리드 + 라벨
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var h = 0; h <= 24; h += 6) {
      final x = size.width * h / 24;
      canvas.drawLine(Offset(x, 0), Offset(x, chartHeight), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '$h시', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final dx = (x - tp.width / 2).clamp(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(dx, chartHeight + 2));
    }

    final curve = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < heights.length; i++) {
      final p0 = pointAt(i - 1);
      final p1 = pointAt(i);
      final cx = (p0.dx + p1.dx) / 2;
      curve.cubicTo(cx, p0.dy, cx, p1.dy, p1.dx, p1.dy);
    }

    final fill = Path.from(curve)
      ..lineTo(size.width, chartHeight)
      ..lineTo(0, chartHeight)
      ..close();
    canvas.drawPath(fill, Paint()..color = fillColor);
    canvas.drawPath(
      curve,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    if (nowFractionOfDay != null) {
      final x = size.width * nowFractionOfDay!;
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, chartHeight),
        Paint()
          ..color = nowColor
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TideChartPainter old) =>
      old.heights != heights || old.nowFractionOfDay != nowFractionOfDay;
}
