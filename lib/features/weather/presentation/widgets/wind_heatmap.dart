import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../data/models/wind_field.dart';

/// Windy.com 기본 바람 레이어 색상 스케일(m/s → RGB).
///
/// **이 값들은 Windy 앱 스크린샷의 하단 범례(legend) 그라데이션을 m/s 눈금
/// 위치(0·3·5·10·15·20·30)에 맞춰 픽셀 단위로 추출해 옮긴 것**이라, 화면 색이
/// Windy와 사실상 일치한다(tool: scratchpad에서 legend 샘플링). Windy 색은
/// 생각보다 **차분한(채도 낮은) 톤**이다: 저속은 연보라→파랑→청록, 중속은
/// 청록끼 도는 초록(예: 5m/s 초록빛 틸, 10m/s 올리브그린), 강풍은 카키→
/// 주황갈색→자주로 간다. 예전의 쨍한 시안·형광 노랑과 달라 바다가 Windy처럼
/// 청록/초록으로 보인다. 색을 다시 맞출 땐 이 추출 절차를 반복한다.
const _stopSpeeds = <double>[
  0,
  2,
  3,
  4,
  5,
  6,
  7,
  8,
  9,
  10,
  11,
  12,
  13,
  14,
  15,
  16,
  17,
  18,
  20,
  23,
  26,
  30,
];
const _stopR = <int>[
  97,
  64,
  72,
  75,
  77,
  74,
  77,
  83,
  92,
  106,
  131,
  155,
  163,
  163,
  160,
  153,
  145,
  143,
  149,
  117,
  94,
  90,
];
const _stopG = <int>[
  111,
  123,
  147,
  146,
  142,
  152,
  161,
  164,
  165,
  162,
  152,
  137,
  128,
  117,
  104,
  88,
  70,
  65,
  74,
  91,
  107,
  136,
];
const _stopB = <int>[
  182,
  165,
  168,
  148,
  122,
  104,
  84,
  71,
  60,
  55,
  61,
  61,
  72,
  83,
  91,
  92,
  93,
  104,
  143,
  156,
  160,
  160,
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

/// 실제 Windy 앱과 **밝기·톤을 맞춘다**. 명도는 그대로 두고 채도만 살짝 올려
/// 색상(hue)은 유지한 채 Windy의 선명한 톤에 맞춘다. 범례 색을 JPEG 스샷에서
/// 뽑아 채도가 약간 죽는 것도 보정할 겸, 파랑 단계가 더 또렷하게 살아나도록
/// ×1.05 → ×1.14로 조금 더 올린다(사용자: "파랑 디테일이 더 살아있었으면").
(int r, int g, int b) _vivid(double rf, double gf, double bf) {
  final hsv = HSVColor.fromColor(
    Color.fromARGB(255, rf.round(), gf.round(), bf.round()),
  );
  final c = hsv
      .withSaturation((hsv.saturation * 1.14).clamp(0.0, 1.0))
      .toColor();
  return ((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round());
}

Color windSpeedColor(double speedMs) {
  final (r, g, b) = windSpeedRgb(speedMs);
  return Color.fromARGB(255, r, g, b);
}

/// [field]를 풍속 기준 색상 래스터([width]×[height])로 구운 이미지를 만든다.
/// 매 프레임이 아니라 필드(시간대)가 바뀔 때만 호출해야 한다.
/// 해상도는 격자(약 1.4° 간격)를 부드럽게 보간해 색 경계가 세밀하게 보이는
/// 정도로 잡는다(픽셀당 약 0.2°).
Future<ui.Image> buildWindHeatmapImage(
  WindField field, {
  // 더 깊은 확대(maxScale)에서도 히트맵이 과하게 블록지지 않도록 래스터를
  // 조금 키운다. 격자(64×66)보다 훨씬 촘촘해 격자 디테일은 그대로 담는다.
  int width = 300,
  int height = 288,
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
