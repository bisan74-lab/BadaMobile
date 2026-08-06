/// 성능 기준선(baseline) 측정.
///
/// 사용자 제보: **화면 첫 로딩이 느리고 바람지도 화면 전환이 버벅인다.**
/// 예전에 측정 없이 원인을 짚었다가 틀린 적이 있어서(캐싱을 의심했는데 실제로는
/// API가 한 번도 성공한 적이 없었다), 고치기 전에 **먼저 숫자를 남긴다.**
///
///     flutter test test/perf/perf_baseline_test.dart
///
/// 출력은 사람이 개선 전후를 비교하기 위한 표이고, `expect`로 못박는 것은
/// **결정적인 횟수**(HTTP 요청 수, 픽셀 수)뿐이다 — 시간 단언은 CI에서
/// 들쭉날쭉해 금방 무시당한다(`perf_probe.dart` 참고).
library;

import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bada_mobile/features/locations/data/models/sea_location.dart';
import 'package:bada_mobile/features/weather/data/models/wind_field.dart';
import 'package:bada_mobile/features/weather/data/repositories/open_meteo_marine_repository.dart';
import 'package:bada_mobile/features/weather/presentation/widgets/coastline_painter.dart';
import 'package:bada_mobile/features/weather/presentation/widgets/country_borders_data.dart';
import 'package:bada_mobile/features/weather/presentation/widgets/map_projection.dart';
import 'package:bada_mobile/features/weather/presentation/widgets/wind_heatmap.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'perf_probe.dart';

const _busan = SeaLocation(
  id: 'busan',
  name: '부산',
  region: '남해',
  latitude: 35.10,
  longitude: 129.05,
);

/// Open-Meteo 응답 흉내. 어떤 변수를 물어봐도 같은 시간축으로 답한다.
String _fakeHourly(Uri uri) {
  final hourly = uri.queryParameters['hourly']?.split(',') ?? const [];
  final times = [
    for (var i = 0; i < 48; i++)
      '2026-08-0${1 + i ~/ 24}T${(i % 24).toString().padLeft(2, '0')}:00',
  ];
  return jsonEncode({
    'hourly': {
      'time': times,
      for (final key in hourly) key: [for (var i = 0; i < 48; i++) 1.0],
    },
  });
}

/// 앱이 실제로 쓰는 것과 같은 크기의 바람장(서버 파일 격자 64×66).
WindField _field() {
  const latSteps = 66, lonSteps = 64;
  final n = latSteps * lonSteps;
  return WindField(
    time: DateTime.utc(2026, 8, 1, 12),
    minLat: 18,
    maxLat: 57,
    minLon: 108,
    maxLon: 148,
    latSteps: latSteps,
    lonSteps: lonSteps,
    u: [for (var i = 0; i < n; i++) 5.0 + (i % 7)],
    v: [for (var i = 0; i < n; i++) -3.0 + (i % 5)],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('기준선 — 지도 히트맵 굽기', () async {
    final field = _field();
    final rows = <Measurement>[];

    // 화면에 실제로 쓰는 두 크기(weather_screen.dart의 값과 같아야 의미가 있다).
    const bgW = 420, bgH = 404;
    const coreW = 1100, coreH = 800;

    late ui.Image bgImage;
    rows.add(
      await measure(
        '배경 전체 bbox',
        () async => bgImage = await buildWindHeatmapImage(field),
        runs: 3,
        detail: '$bgW×$bgH = ${bgW * bgH ~/ 1000}K px',
      ),
    );
    bgImage.dispose();

    late ui.Image coreImage;
    rows.add(
      await measure(
        '핵심영역 고해상도',
        () async => coreImage = await buildWindHeatmapImage(
          field,
          crop: const LatLonBounds(
            minLat: 28,
            maxLat: 44,
            minLon: 116,
            maxLon: 138,
          ),
          width: coreW,
          height: coreH,
        ),
        runs: 3,
        detail: '$coreW×$coreH = ${coreW * coreH ~/ 1000}K px',
      ),
    );
    coreImage.dispose();

    printReport('바람지도 시간 스텝 1회당 굽는 비용', rows);

    // 결정적 단언: 시간 스텝을 한 번 옮길 때 계산하는 픽셀 수.
    //
    // **드래그 중에는 배경만 굽는다**(`_WindMapArea.scrubbing`). 고해상도
    // 핵심영역은 손을 뗀 뒤 딱 한 번 굽고, 그때 배경은 이미 구워져 있으니
    // 다시 굽지 않는다. 그래서 슬라이더를 N칸 끌면
    //   배경 N번 + 핵심영역 1번
    // 이고, 예전(칸마다 두 장)의 `N × 1049680`과 비교된다.
    const scrubPx = bgW * bgH; // 드래그 중 한 칸당
    const releasePx = coreW * coreH; // 손 뗀 뒤 한 번
    expect(scrubPx, 169680, reason: '드래그 중 한 칸당 계산 픽셀 수');
    expect(releasePx, 880000, reason: '손을 뗀 뒤 한 번만 계산하는 픽셀 수');

    // 8칸을 끄는 동안의 총량 — 개선 효과를 한 숫자로 본다.
    const steps = 8;
    const before = steps * (scrubPx + releasePx);
    const after = steps * scrubPx + releasePx;
    // ignore: avoid_print
    print(
      '  슬라이더 $steps칸: ${before ~/ 1000}K px → ${after ~/ 1000}K px '
      '(${(100 - after * 100 / before).round()}% 감소)\n',
    );
    expect(after, lessThan(before ~/ 2), reason: '스크럽 최적화 효과');
  });

  test('기준선 — 해안선 Path 생성', () async {
    const size = Size(800, 1400);
    final projection = MapProjection(mapViewBounds, size);
    final rows = <Measurement>[];

    // CustomPainter.paint를 직접 부르는 대신 실제 캔버스에 그린다.
    Future<void> paintOnce(double scale) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      CoastlinePainter(
        projection: projection,
        scale: scale,
      ).paint(canvas, size);
      recorder.endRecording().dispose();
    }

    rows.add(
      await measure('기본 배율(2.1)', () => paintOnce(2.1), detail: '해안선·국경만'),
    );
    rows.add(
      await measure('확대(8.0)', () => paintOnce(8.0), detail: '행정·강 레이어까지'),
    );

    printReport('지도를 확대·팬할 때마다 다시 그리는 비용', rows);

    // 좌표가 몇 개인지 — Path 생성 비용의 실체.
    var points = 0;
    for (final polylines in countryBorders.values) {
      for (final line in polylines) {
        points += line.length;
      }
    }
    // ignore: avoid_print
    print('  해안선 좌표 총 $points개 (레이어 ${countryBorders.length}종)\n');
    expect(points, greaterThan(10000), reason: '좌표 수가 갑자기 줄면 지도가 성겨진 것');
  });

  test('기준선 — 지점 상세 예보 네트워크 호출', () async {
    // 지도에서 지점을 탭하면 상세 예보가 뜬다. 그때 몇 건을 던지는가.
    final client = CountingClient(
      respond: _fakeHourly,
      // 실제 Open-Meteo 왕복을 흉내 낸다(한국에서 대략 이 정도).
      latency: const Duration(milliseconds: 120),
    );
    final repo = OpenMeteoMarineRepository(client: client);

    final first = await measure(
      '첫 조회',
      () async => repo.fetchForecast(_busan),
      runs: 1,
    );
    final firstCount = client.count;
    final endpoints = client.byEndpoint;

    client.reset();
    final second = await measure(
      '같은 지점 재조회',
      () async => repo.fetchForecast(_busan),
      runs: 1,
    );
    final secondCount = client.count;

    printReport('지도에서 지점을 탭했을 때', [
      Measurement(first.label, first.elapsed, detail: 'HTTP $firstCount건'),
      Measurement(second.label, second.elapsed, detail: 'HTTP $secondCount건'),
    ]);
    // ignore: avoid_print
    print('  엔드포인트별: $endpoints\n');

    // **여기가 핵심 지표다.** 지금은 지점 하나당 5건(GFS 파랑·WAM 총파고·
    // WAM 너울·수온·육상예보)을 던진다. 줄이면 이 수가 줄어든다.
    expect(firstCount, 5, reason: '지점 1곳 상세 예보의 HTTP 요청 수');
    // 같은 지점을 다시 봐도 또 5건을 던진다 — 캐시가 없다는 뜻이고,
    // 개선하면 이 값이 0이 되어야 한다.
    expect(secondCount, 5, reason: '재조회 시 요청 수(캐시가 생기면 0)');
  });
}
