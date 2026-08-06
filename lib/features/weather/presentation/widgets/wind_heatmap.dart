import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../../data/models/wind_field.dart';
import 'map_projection.dart';

/// 바람 세기(m/s) → RGB 색상 스케일.
///
/// 중간 구간(0~26m/s)은 채도 낮은 청록·올리브·카키·자주 톤으로, 저속은
/// 연보라→파랑, 중속은 청록끼 도는 초록·올리브그린, 강풍은 카키→주황갈색→
/// 자주로 이어진다. **30m/s만 짙은 남색-검정**으로 다시 잡아, 위험할수록
/// 어두워지는 인상을 준다(0m/s는 원래 톤 그대로 — 밝게 바꿔봤다가 어색해서
/// 되돌렸다).
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
  22,
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
  34,
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
  46,
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

/// 고정 시드 값 노이즈(fractal Brownian motion). Windy 특유의 잘게
/// 소용돌이치는 텍스처는 실제 모델 격자로는 다 담기 힘든 중규모 난류
/// (mesoscale turbulence)까지 시각적으로 표현한 것에 가깝다. 실제 바람장
/// 값은 바꾸지 않고, 색을 뽑을 좌표만 풍속에 비례해 이 노이즈로 살짝
/// 뒤트는(domain warp) 방식으로 같은 효과를 낸다. 시드가 고정이라 같은
/// 위치는 항상 같은 방식으로 뒤틀려 시간이 지나도 지글거리지 않는다.
class _TurbulenceNoise {
  const _TurbulenceNoise(this.seed);
  final int seed;

  double _hash(int x, int y) {
    var h = x * 374761393 + y * 668265263 + seed * 2654435761;
    h = (h ^ (h >> 13)) * 1274126177;
    h = h ^ (h >> 16);
    return ((h & 0x7fffffff) / 0x7fffffff) * 2 - 1;
  }

  double _smooth(double t) => t * t * (3 - 2 * t);

  double _valueNoise(double x, double y) {
    final xi = x.floor(), yi = y.floor();
    final xf = x - xi, yf = y - yi;
    final n00 = _hash(xi, yi);
    final n10 = _hash(xi + 1, yi);
    final n01 = _hash(xi, yi + 1);
    final n11 = _hash(xi + 1, yi + 1);
    final u = _smooth(xf), v = _smooth(yf);
    double lerp(double a, double b, double t) => a + (b - a) * t;
    return lerp(lerp(n00, n10, u), lerp(n01, n11, u), v);
  }

  /// 옥타브를 겹쳐(fbm) 크고 작은 소용돌이가 함께 섞이게 한다.
  double fbm(double x, double y) {
    var sum = 0.0, amp = 0.6, freq = 1.0;
    for (var i = 0; i < 3; i++) {
      sum += amp * _valueNoise(x * freq, y * freq);
      freq *= 2.15;
      amp *= 0.55;
    }
    return sum;
  }
}

const _turbulence = _TurbulenceNoise(20260722);
// 노이즈 한 주기가 대략 이 경도/위도(°)가 되게 하는 주파수(중규모 소용돌이
// 크기 감). 값이 클수록 더 잘게 소용돌이친다.
const _turbNoiseFreq = 2.6;
// 최대 뒤틀림 거리(°) — 풍속이 빠를수록(난류가 강할수록) 이 값에 가까워지고,
// 약풍·무풍 지역은 거의 뒤틀리지 않아 매끈하게 남는다.
const _turbMaxWarpDeg = 0.16;
// **풍속 변조**: 좌표 워프와 별개로, 색을 정할 풍속 자체를 고주파 FBM으로
// ±(k×풍속)만큼 흔든다. 0.25~0.87° 격자를 bicubic으로 매끈하게 보간한 장에는
// Windy처럼 1~3m/s짜리 국지 얼룩(중규모 난류)이 원천적으로 없어서, 좌표만
// 비틀어서는(부드러운 장을 부드럽게 비틀 뿐) 화면 질감이 거의 안 변한다 —
// 실측으로 확인(8px 색차 "뚜렷" 비율: Windy 15% vs 우리 7%). 풍속에
// 비례하므로 무풍 해역은 여전히 매끈하다. u/v 원본·지점 예보 수치는 불변.
// 실측 튜닝: 실배포 데이터 렌더로 8px 색차 분포를 Windy와 맞춘 값
// (k=0.18에서 "뚜렷" 14.3% vs Windy 15.1%, "평탄" 58% vs 61%).
const _speedModAmp = 0.18; // 변조 진폭(풍속의 ±18%)
const _speedModFreq = 8.0; // 얼룩 크기 감(클수록 잘게, 약 1/8° 스케일)
// 위 배율(×) 변조만으로는 저풍속(파란) 해역이 절대량으로 거의 안 흔들려
// (예: 2m/s×18%=0.36m/s) 팔레트 단계 경계를 잘 못 넘어, 초록·강풍대만
// 얼룩지고 파랑대는 밋밋해 보였다(사용자 피드백: "파란색 디테일 부족").
// 그래서 풍속 크기와 무관한 절대 변조(±1.0m/s)를 더한다 — 저속에서도
// 팔레트 단계를 넘나들 만큼은 흔들리면서, 고속에서는 배율 항에 묻힌다.
// 실측: 저속(0~6m/s) 구간 8px "뚜렷" 비율 12.7%→25.1%로 개선.
const _speedModAddMs = 1.0;
const _speedModAddFreq = 6.0;

/// [field]를 풍속 기준 색상 래스터([width]×[height])로 구운 이미지를 만든다.
/// 매 프레임이 아니라 필드(시간대)가 바뀔 때만 호출해야 한다.
/// [crop]을 주면 그 위경도 범위만 굽는다(한반도 핵심영역 고해상도 오버레이용,
/// null이면 필드 전체 bbox — 기존 호출과 동일). 픽셀 루프는 [compute]
/// 아이솔레이트에서 돌아 큰 래스터도 UI 프레임을 막지 않는다.
Future<ui.Image> buildWindHeatmapImage(
  WindField field, {
  LatLonBounds? crop,
  // 더 깊은 확대(maxScale)에서도 히트맵이 과하게 블록지지 않도록 래스터를
  // 조금 키운다. 격자(64×66)보다 훨씬 촘촘해 격자 디테일은 그대로 담는다.
  int width = 420,
  int height = 404,
}) async {
  final minLat = crop?.minLat ?? field.minLat;
  final maxLat = crop?.maxLat ?? field.maxLat;
  final minLon = crop?.minLon ?? field.minLon;
  final maxLon = crop?.maxLon ?? field.maxLon;

  // **가로 띠로 나눠 여러 아이솔레이트에서 동시에 굽는다.**
  //
  // 픽셀 하나마다 bicubic 샘플 2번 + FBM 노이즈 4번이 돌아 88만 px짜리
  // 핵심영역은 한 아이솔레이트에서 1.5초가 넘는다(실측). 사용자 제보로는
  // 실기기에서 슬라이더를 놓고 지도가 바뀌기까지 약 3초 걸렸다.
  // 픽셀끼리 서로를 참조하지 않으므로 행 단위로 그냥 쪼개면 된다.
  final bands = _bandCount(width * height);
  final buffer = bands == 1
      ? await compute(_fillHeatmapPixels, (
          field: field,
          minLat: minLat,
          maxLat: maxLat,
          minLon: minLon,
          maxLon: maxLon,
          width: width,
          height: height,
          yStart: 0,
          yEnd: height,
        ))
      : await _fillInBands(
          field: field,
          minLat: minLat,
          maxLat: maxLat,
          minLon: minLon,
          maxLon: maxLon,
          width: width,
          height: height,
          bands: bands,
        );
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

/// 이 래스터를 몇 개의 띠로 나눠 구울지.
///
/// 아이솔레이트를 띄우는 데도 비용이 있어(수십 ms) 작은 래스터는 오히려
/// 손해다. 기기 코어 수를 넘겨 봐야 서로 밀어내기만 하므로 거기서 자른다.
int _bandCount(int pixels) {
  final byCores = Platform.numberOfProcessors;
  final bySize = pixels >= 400000
      ? 4
      : pixels >= 150000
      ? 2
      : 1;
  return bySize.clamp(1, byCores < 1 ? 1 : byCores);
}

/// 가로 띠로 나눠 동시에 굽고 하나로 잇는다.
///
/// 각 띠는 **전체 높이 기준의 y 범위**를 받는다 — 띠마다 자기 높이로
/// 위경도를 계산하면 띠 경계에서 색이 끊긴다.
Future<Uint8List> _fillInBands({
  required WindField field,
  required double minLat,
  required double maxLat,
  required double minLon,
  required double maxLon,
  required int width,
  required int height,
  required int bands,
}) async {
  final rows = (height / bands).ceil();
  final parts = await Future.wait([
    for (var i = 0; i < bands; i++)
      if (i * rows < height)
        compute(_fillHeatmapPixels, (
          field: field,
          minLat: minLat,
          maxLat: maxLat,
          minLon: minLon,
          maxLon: maxLon,
          width: width,
          height: height,
          yStart: i * rows,
          yEnd: math.min((i + 1) * rows, height),
        )),
  ]);
  final buffer = Uint8List(width * height * 4);
  var offset = 0;
  for (final part in parts) {
    buffer.setRange(offset, offset + part.length, part);
    offset += part.length;
  }
  return buffer;
}

/// 픽셀 채우기(아이솔레이트에서 실행). [WindField]는 프리미티브 리스트로만
/// 구성돼 isolate 경계를 그대로 넘는다.
///
/// [args.yStart]~[args.yEnd] 행만 채운 바이트를 돌려준다. 위경도 계산은
/// **전체 [args.height]** 기준이라 띠를 이어 붙여도 이음매가 생기지 않는다.
Uint8List _fillHeatmapPixels(
  ({
    WindField field,
    double minLat,
    double maxLat,
    double minLon,
    double maxLon,
    int width,
    int height,
    int yStart,
    int yEnd,
  })
  args,
) {
  final field = args.field;
  final width = args.width, height = args.height;
  final buffer = Uint8List(width * (args.yEnd - args.yStart) * 4);
  var idx = 0;
  for (var y = args.yStart; y < args.yEnd; y++) {
    final ty = height == 1 ? 0.0 : y / (height - 1);
    final lat = args.maxLat - ty * (args.maxLat - args.minLat);
    for (var x = 0; x < width; x++) {
      final tx = width == 1 ? 0.0 : x / (width - 1);
      final lon = args.minLon + tx * (args.maxLon - args.minLon);
      final uv0 = field.sample(lat, lon);
      var r = 0, g = 0, b = 0, a = 0;
      if (uv0 != null) {
        final (u0, v0) = uv0;
        final speed0 = math.sqrt(u0 * u0 + v0 * v0);
        // 풍속이 빠를수록 뒤틀림을 키운다(0 m/s→0, 8 m/s 근방부터 최대치에
        // 가까워짐) — 실제 난류가 강한 곳일수록 더 세밀하게 흔들리게 한다.
        final warpAmp =
            _turbMaxWarpDeg * (speed0 / (speed0 + 8)).clamp(0.0, 1.0);
        final nx = _turbulence.fbm(lon * _turbNoiseFreq, lat * _turbNoiseFreq);
        final ny = _turbulence.fbm(
          lon * _turbNoiseFreq + 57.3,
          lat * _turbNoiseFreq + 57.3,
        );
        final wLat = lat + ny * warpAmp;
        final wLon = lon + nx * warpAmp;
        final uv = field.sample(wLat, wLon) ?? uv0;
        final (u, v) = uv;
        var speed = math.sqrt(u * u + v * v);
        // 풍속 변조(위 상수 주석 참고): 고주파 FBM으로 국지 얼룩을 만든다.
        // 좌표 워프 노이즈와 시드 좌표를 어긋나게(오프셋) 해 상관을 끊는다.
        final m = _turbulence.fbm(
          lon * _speedModFreq + 113.7,
          lat * _speedModFreq + 113.7,
        );
        speed *= 1 + _speedModAmp * m;
        // 절대 변조(저속대 디테일용) — 별도 주파수/오프셋 노이즈로 배율
        // 변조와 상관을 끊는다.
        final mAdd = _turbulence.fbm(
          lon * _speedModAddFreq + 271.1,
          lat * _speedModAddFreq + 271.1,
        );
        speed = math.max(0.0, speed + _speedModAddMs * mAdd);
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
  return buffer;
}

/// 미리 구운 풍속 색상 래스터를 [dstRect] 영역에 맞춰 확대해 그린다.
/// [dstRect]는 지도 전체 투영 위에서 바람장 격자가 차지하는 위치다
/// (지도 뷰가 바람장보다 넓을 수 있어 전체 캔버스를 채우지 않을 수 있다).
///
/// [coreImage]가 있으면 그 위에 한반도 핵심영역 고해상도 래스터를
/// [coreDstRect] 위치에 덧그린다 — 전체 bbox 래스터(420×404)는 남한을
/// ~63×62px로만 담아 확대 시 뭉개지므로, 사용자가 실제로 보는 핵심영역만
/// 따로 촘촘하게 구워 그 위에 겹친다(밖으로 팬하면 배경 래스터가 보인다).
class WindHeatmapPainter extends CustomPainter {
  WindHeatmapPainter({
    required this.image,
    required this.dstRect,
    this.coreImage,
    this.coreDstRect,
  });

  final ui.Image image;
  final Rect dstRect;
  final ui.Image? coreImage;
  final Rect? coreDstRect;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.high;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dstRect,
      paint,
    );
    final core = coreImage;
    final coreRect = coreDstRect;
    if (core != null && coreRect != null) {
      canvas.drawImageRect(
        core,
        Rect.fromLTWH(0, 0, core.width.toDouble(), core.height.toDouble()),
        coreRect,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WindHeatmapPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.dstRect != dstRect ||
      oldDelegate.coreImage != coreImage ||
      oldDelegate.coreDstRect != coreDstRect;
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
