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

    // 핵심: 관찰된 모든 상태에서 두 장이 항상 함께 바뀌어야 한다.
    // 배경만 바뀐 중간 상태가 하나라도 있으면 실패.
    for (var i = 1; i < seen.length; i++) {
      final prev = seen[i - 1], now = seen[i];
      final bgChanged = !identical(prev.$1, now.$1);
      final coreChanged = !identical(prev.$2, now.$2);
      expect(
        bgChanged && coreChanged,
        isTrue,
        reason:
            '$i번째 상태에서 한 장만 바뀌었다 '
            '(배경 ${bgChanged ? '변경' : '유지'}, '
            '핵심영역 ${coreChanged ? '변경' : '유지'}) '
            '— 새 시각 배경 위에 옛 시각 핵심영역이 덮이는 순간이다',
      );
    }

    // 핵심영역이 null로 비는 순간도 없어야 한다(비면 배경만 확대돼 뭉개진다).
    for (final s in seen) {
      expect(s.$2, isNotNull, reason: '핵심영역 없이 배경만 그려진 순간이 있다');
    }
  });
}
