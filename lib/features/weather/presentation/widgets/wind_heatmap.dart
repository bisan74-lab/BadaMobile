import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/models/wind_field.dart';

/// Windy.com의 기본 바람 레이어 색상 스케일(m/s → RGB)을 그대로 옮긴 것.
/// 보라(정온) → 파랑 → 청록 → 초록 → 카키/노랑 → 주황갈색 → 자주 …로
/// 이어지는 Windy 고유 그라데이션이라 화면 색이 Windy 앱과 일치한다.
const _stopSpeeds = <double>[
  0,
  1,
  3,
  5,
  7,
  9,
  11,
  13,
  15,
  17,
  19,
  21,
  24,
  27,
  29,
  36,
  46.5,
  51.5,
  77,
];
const _stopR = <int>[
  98,
  57,
  74,
  77,
  83,
  53,
  167,
  159,
  161,
  129,
  175,
  117,
  109,
  68,
  92,
  125,
  231,
  219,
  205,
];
const _stopG = <int>[
  113,
  97,
  148,
  141,
  165,
  159,
  157,
  127,
  108,
  58,
  80,
  74,
  97,
  105,
  144,
  68,
  215,
  212,
  202,
];
const _stopB = <int>[
  183,
  159,
  169,
  123,
  83,
  53,
  81,
  58,
  92,
  78,
  136,
  147,
  163,
  141,
  152,
  165,
  215,
  135,
  112,
];

(int r, int g, int b) windSpeedRgb(double speedMs) {
  final s = speedMs.clamp(0.0, _stopSpeeds.last);
  for (var i = 0; i < _stopSpeeds.length - 1; i++) {
    if (s <= _stopSpeeds[i + 1]) {
      final t = (s - _stopSpeeds[i]) / (_stopSpeeds[i + 1] - _stopSpeeds[i]);
      return _vivid(
        _stopR[i] + (_stopR[i + 1] - _stopR[i]) * t,
        _stopG[i] + (_stopG[i + 1] - _stopG[i]) * t,
        _stopB[i] + (_stopB[i + 1] - _stopB[i]) * t,
      );
    }
  }
  return _vivid(
    _stopR.last.toDouble(),
    _stopG.last.toDouble(),
    _stopB.last.toDouble(),
  );
}

/// windy.com 기본 그라데이션은 중간 풍속대(카키·갈색)가 탁해 보여 실제
/// Windy 앱보다 색이 약하게 느껴진다. 색상(hue)은 그대로 두고 채도·명도만
/// 살짝 끌어올려 초록·노랑·주황이 또렷하게 살아나게 한다(윈디 앱 느낌).
(int r, int g, int b) _vivid(double rf, double gf, double bf) {
  final hsv = HSVColor.fromColor(
    Color.fromARGB(255, rf.round(), gf.round(), bf.round()),
  );
  final c = hsv
      .withSaturation((hsv.saturation * 1.32).clamp(0.0, 1.0))
      .withValue((hsv.value * 1.06).clamp(0.0, 1.0))
      .toColor();
  return ((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round());
}

Color windSpeedColor(double speedMs) {
  final (r, g, b) = windSpeedRgb(speedMs);
  return Color.fromARGB(255, r, g, b);
}

/// [field]를 풍속 기준 색상 래스터([width]×[height])로 구운 이미지를 만든다.
/// 매 프레임이 아니라 필드(시간대)가 바뀔 때만 호출해야 한다.
Future<ui.Image> buildWindHeatmapImage(
  WindField field, {
  int width = 144,
  int height = 108,
}) {
  final buffer = Uint8List(width * height * 4);
  var idx = 0;
  for (var y = 0; y < height; y++) {
    final ty = height == 1 ? 0.0 : y / (height - 1);
    final lat = field.maxLat - ty * (field.maxLat - field.minLat);
    for (var x = 0; x < width; x++) {
      final tx = width == 1 ? 0.0 : x / (width - 1);
      final lon = field.minLon + tx * (field.maxLon - field.minLon);
      final uv = field.sample(lat, lon);
      var r = 0, g = 0, b = 0, a = 0;
      if (uv != null) {
        final (u, v) = uv;
        final speed = math.sqrt(u * u + v * v);
        final rgb = windSpeedRgb(speed);
        r = rgb.$1;
        g = rgb.$2;
        b = rgb.$3;
        a = 255;
      }
      buffer[idx++] = r;
      buffer[idx++] = g;
      buffer[idx++] = b;
      buffer[idx++] = a;
    }
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    buffer,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// 미리 구운 풍속 색상 래스터를 [dstRect] 영역에 맞춰 확대해 그린다.
/// [dstRect]는 지도 전체 투영 위에서 바람장 격자가 차지하는 위치다
/// (지도 뷰가 바람장보다 넓을 수 있어 전체 캔버스를 채우지 않을 수 있다).
class WindHeatmapPainter extends CustomPainter {
  WindHeatmapPainter({required this.image, required this.dstRect});

  final ui.Image image;
  final Rect dstRect;

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    canvas.drawImageRect(
      image,
      src,
      dstRect,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(covariant WindHeatmapPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.dstRect != dstRect;
}

/// 지도 아래 붙는 풍속 색상 범례(0~30+ m/s), 윈디 하단 스케일바 스타일.
class WindSpeedLegend extends StatelessWidget {
  const WindSpeedLegend({super.key});

  static const _marks = [0, 3, 5, 10, 15, 20, 30];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                colors: [
                  for (var s = 0; s <= 30; s++) windSpeedColor(s.toDouble()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final m in _marks)
                Text('$m', style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
          Text(
            'm/s · 바람 세기',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
