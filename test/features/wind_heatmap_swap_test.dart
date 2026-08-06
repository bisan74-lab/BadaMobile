import 'dart:ui' as ui;

import 'package:bada_mobile/core/storage/prefs.dart';
import 'package:bada_mobile/features/weather/data/repositories/mock_wind_field_repository.dart';
import 'package:bada_mobile/features/weather/presentation/weather_screen.dart';
import 'package:bada_mobile/features/weather/presentation/widgets/wind_heatmap.dart';
import 'package:bada_mobile/features/weather/presentation/wind_field_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 시간 슬라이더를 옮길 때 히트맵이 **한 번에** 바뀌는지 확인한다.
///
/// 지도는 래스터 두 장으로 그린다 — 전체 bbox 배경(저해상도)과 한반도
/// 핵심영역(고해상도). 예전엔 배경을 먼저 화면에 올리고 핵심영역을 이어서
/// 올려서, 그 사이 몇 프레임 동안 **새 시각의 배경 + 직전 시각의 핵심영역**이
/// 겹쳐 그려졌다. 화면에서는 핵심영역 밖(아래쪽 띠)만 먼저 바뀌었다가 잠시 뒤
/// 전체가 바뀌는 것처럼 보인다(사용자 제보. 영상 실측으로 약 0.12초 간격 확인).
///
/// 그래서 여기서는 프레임마다 painter가 들고 있는 이미지 두 장을 기록해,
/// **배경만 바뀐 프레임이 한 번도 없는지**를 본다.
void main() {
  // 파티클 애니메이션 Ticker 때문에 pumpAndSettle은 쓰지 않는다.
  testWidgets('시간을 옮겨도 배경과 핵심영역이 따로 바뀌지 않는다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          windFieldRepositoryProvider.overrideWithValue(
            MockWindFieldRepository(),
          ),
        ],
        child: const MaterialApp(home: WeatherScreen()),
      ),
    );

    /// 지금 그려지고 있는 히트맵 이미지 두 장. 아직 없으면 null.
    (ui.Image, ui.Image?)? current() {
      for (final paint in tester.widgetList<CustomPaint>(
        find.byType(CustomPaint),
      )) {
        final p = paint.painter;
        if (p is WindHeatmapPainter) return (p.image, p.coreImage);
      }
      return null;
    }

    final seen = <(ui.Image, ui.Image?)>[];

    /// 프레임을 진행하면서 매 프레임 painter 상태를 기록한다.
    ///
    /// 히트맵은 `compute()`(진짜 아이솔레이트)와 `decodeImageFromPixels`로
    /// 구워지므로, 테스트의 가짜 시간만으로는 완료되지 않는다. 프레임 사이에
    /// [WidgetTester.runAsync]로 실제 시간을 조금씩 흘려 보내야 한다.
    Future<void> pumpFrames(int count) async {
      for (var i = 0; i < count; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
        final now = current();
        if (now != null &&
            (seen.isEmpty ||
                !identical(seen.last.$1, now.$1) ||
                !identical(seen.last.$2, now.$2))) {
          seen.add(now);
        }
      }
    }

    await tester.pump(); // FutureProvider 완료
    await pumpFrames(40);
    expect(seen, isNotEmpty, reason: '히트맵이 한 번도 안 그려졌다');
    final firstCount = seen.length;

    // 시간 슬라이더를 옮긴다(래스터 두 장을 다시 굽는 데 시간이 걸려
    // 스텝을 늘리면 테스트가 그만큼 길어진다 — 두 번이면 충분히 잡힌다).
    for (final step in [3, 7]) {
      final slider = tester.widget<Slider>(find.byType(Slider).first);
      slider.onChanged!(step.toDouble());
      await pumpFrames(40);
    }

    expect(
      seen.length,
      greaterThan(firstCount),
      reason: '시간을 옮겼는데 히트맵이 다시 구워지지 않았다',
    );

    // **핵심 불변식: 배경이 바뀌었는데 핵심영역이 옛것 그대로면 안 된다.**
    //
    // 그 상태가 곧 "새 시각 배경 + 옛 시각 핵심영역"이고, 화면에서는
    // 핵심영역 밖(아래쪽 띠)만 먼저 바뀐 것처럼 보인다.
    //
    // 반대로 **핵심영역이 없는(null) 상태는 허용**한다. 시간 슬라이더를 끄는
    // 동안 일부러 배경만 굽기 때문이다(고해상도는 배경의 5배 비용이라 매 칸
    // 구우면 슬라이더가 밀린다). 이때 화면은 해상도만 낮을 뿐 **전체가 같은
    // 시각**이라 시각이 섞이지 않는다.
    for (var i = 1; i < seen.length; i++) {
      final prev = seen[i - 1], now = seen[i];
      final bgChanged = !identical(prev.$1, now.$1);
      final coreKeptOld = now.$2 != null && identical(prev.$2, now.$2);
      expect(
        bgChanged && coreKeptOld,
        isFalse,
        reason:
            '$i번째 상태: 배경은 새 시각인데 핵심영역이 옛 시각 그대로다 '
            '— 화면 아래쪽 띠만 먼저 바뀌어 보이는 그 증상이다',
      );
    }
  });

  testWidgets('슬라이더를 끄는 동안엔 고해상도를 굽지 않는다', (tester) async {
    // 성능 개선의 핵심 동작. 드래그 중에는 배경만 갱신하고(약 1/5 비용),
    // 손을 뗀 뒤에 고해상도를 채운다.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          windFieldRepositoryProvider.overrideWithValue(
            MockWindFieldRepository(),
          ),
        ],
        child: const MaterialApp(home: WeatherScreen()),
      ),
    );

    ui.Image? core() {
      for (final paint in tester.widgetList<CustomPaint>(
        find.byType(CustomPaint),
      )) {
        final p = paint.painter;
        if (p is WindHeatmapPainter) return p.coreImage;
      }
      return null;
    }

    Future<void> settle(int frames) async {
      for (var i = 0; i < frames; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    await tester.pump();
    await settle(40);
    expect(core(), isNotNull, reason: '처음엔 고해상도까지 그려져 있어야 한다');

    // 슬라이더를 잡고 몇 칸 끈다.
    final slider = tester.widget<Slider>(find.byType(Slider).first);
    slider.onChangeStart!(0);
    slider.onChanged!(4);
    await settle(30);
    expect(core(), isNull, reason: '드래그 중에는 고해상도를 굽지 않아야 한다(배경만)');

    // 손을 뗀다 → 그제서야 고해상도가 채워진다.
    slider.onChangeEnd!(4);
    await settle(60);
    expect(core(), isNotNull, reason: '손을 떼면 고해상도가 채워져야 한다');
  });
}
