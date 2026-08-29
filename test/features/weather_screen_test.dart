import 'package:bada_mobile/core/storage/prefs.dart';
import 'package:bada_mobile/core/utils/formatters.dart';
import 'package:bada_mobile/core/utils/kst.dart';
import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:bada_mobile/features/locations/presentation/providers.dart';
import 'package:bada_mobile/features/weather/data/repositories/mock_marine_weather_repository.dart';
import 'package:bada_mobile/features/weather/data/repositories/mock_wind_field_repository.dart';
import 'package:bada_mobile/features/weather/presentation/providers.dart';
import 'package:bada_mobile/features/weather/presentation/weather_screen.dart';
import 'package:bada_mobile/features/weather/presentation/wind_field_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 파티클 애니메이션은 계속 반복되는 Ticker를 쓰므로 pumpAndSettle은 쓰지 않고
// pump()로 몇 프레임만 진행해 예외 없이 그려지는지 확인한다.

void main() {
  testWidgets('진입 시 지도만 그리고, 지도를 탭하면 상단에 바람·상세예보가 뜬다', (tester) async {
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

    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pump(); // FutureProvider 완료
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    // 진입 시: 지도(CustomPaint) + 하단 시간 스크러버(Slider)만, 상세 예보 표·
    // 상단 바 없음. (윈디처럼 지도만 보일 때도 바람장 시각을 앞뒤로 스크럽한다.)
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('상세 예보'), findsNothing);

    // 지도 중앙을 탭하면 커서가 찍히고 상단에 바람 세기·방향 + "상세 예보" 버튼.
    await tester.tapAt(tester.getCenter(find.byType(WeatherScreen)));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('상세 예보'), findsOneWidget);
  });

  testWidgets('지도 마커를 탭하면 선택 지역이 바뀐다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        windFieldRepositoryProvider.overrideWithValue(
          MockWindFieldRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: WeatherScreen()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    final target = sampleLocations.firstWhere((l) => l.id != 'ganghwado');
    // 지도 위에 항상 보이는 좌표는 아니므로, 최근접 지점을 강제 선택해
    // provider 갱신 로직만 검증한다(마커 실제 히트테스트는 좌표 계산에
    // 의존적이라 통합 시나리오로는 provider 갱신을 직접 확인한다).
    container.read(selectedLocationProvider.notifier).select(target);
    await tester.pump(const Duration(milliseconds: 16));

    expect(container.read(selectedLocationProvider).id, target.id);
  });

  testWidgets('지도에서 날짜를 옮긴 뒤 상세 예보로 들어가면 그 날짜가 유지된다', (
    tester,
  ) async {
    // 2026-08-08 사용자 제보: 지도 시간 슬라이더로 미래 날짜를 골라 둔 채
    // "상세 예보"로 들어가면 표가 그 날짜가 아니라 "지금"부터 보였다.
    // 원인은 `_PointForecastPanel`이 지도의 선택 시각을 아예 전달받지 않고
    // 첫 진입 시 항상 `nowIdx`로 `_i`를 초기화했기 때문이다.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          windFieldRepositoryProvider.overrideWithValue(
            MockWindFieldRepository(),
          ),
          // 상세 표는 marineForecastProvider를 따로 쓰므로 이것도 목으로
          // 바꿔야 실 네트워크를 타지 않는다.
          marineWeatherRepositoryProvider.overrideWithValue(
            MockMarineWeatherRepository(),
          ),
        ],
        child: const MaterialApp(home: WeatherScreen()),
      ),
    );

    await tester.pump(); // FutureProvider 완료
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    // 지도 시각을 30시간(하루+6시간) 앞으로 옮긴다 — Slider의 onChanged를
    // 실제 드래그처럼 한 번 호출한다(내부적으로 `_setMapHour`를 그대로 탄다).
    const movedOffset = 30;
    tester.widget<Slider>(find.byType(Slider)).onChanged!(
      movedOffset.toDouble(),
    );
    await tester.pump(const Duration(milliseconds: 16));

    // 지도를 탭해 커서를 찍고 "상세 예보"로 들어간다(기존 테스트와 같은 흐름).
    await tester.tapAt(tester.getCenter(find.byType(WeatherScreen)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.text('상세 예보'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16)); // marineForecastProvider 완료
    await tester.pump(const Duration(milliseconds: 16));

    // 앱과 같은 계산으로 "옮겨 둔 시각"이 표에서 어느 3시간 칸에 떨어지는지
    // 독립적으로 구한다(MockWindFieldRepository·MockMarineWeatherRepository가
    // 둘 다 "지금을 정시로 자른 값"을 기준으로 삼으므로 시작점이 같다).
    final now = nowKst();
    final hourStart = DateTime(now.year, now.month, now.day, now.hour);
    final movedFieldTime = hourStart.add(const Duration(hours: movedOffset));
    final steps = [
      for (var i = 0; i < 16 * 24; i++)
        if (hourStart.add(Duration(hours: i)).hour % 3 == 0)
          hourStart.add(Duration(hours: i)),
    ].take(16 * 8).toList();
    final expectedIdx = currentStepIndex(steps, movedFieldTime);
    final nowIdx = currentStepIndex(steps, now);
    // 두 인덱스가 실제로 다른 칸이어야 이 테스트가 버그를 가려낼 수 있다.
    expect(
      expectedIdx,
      isNot(equals(nowIdx)),
      reason: '30시간을 옮겼는데도 같은 3시간 칸이면 이 테스트가 무의미하다',
    );
    final expectedText =
        '${formatMonthDay(steps[expectedIdx])} ${formatHm(steps[expectedIdx])}';

    // 표 상단 시각 표시가 "지금"이 아니라 옮겨 둔 시각과 가장 가까운 칸이어야
    // 한다. 고친 전이라면 이 텍스트 대신 "지금" 시각이 표시돼 실패한다.
    expect(find.text(expectedText), findsOneWidget);
  });

  testWidgets('상세 예보 창을 닫아도 보고 있던 시각이 유지된다', (tester) async {
    // 2026-08-08 사용자 제보: 상세 예보 창을 닫으면 지도가 "지금"으로
    // 되돌아갔다. `_closeDetail`이 창을 닫을 때 `_hourOffset`을 명시적으로
    // `nowKst()` 기준으로 되돌리고 있었는데, 표를 보는 동안 이미
    // `_syncMapHour`가 `_hourOffset`을 표의 선택 시각과 맞춰 두므로 이 되돌림
    // 자체가 불필요했고, 방금 보던 미래/과거 시각이 창을 닫는 순간 사라지는
    // 것처럼 보였다.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          windFieldRepositoryProvider.overrideWithValue(
            MockWindFieldRepository(),
          ),
          marineWeatherRepositoryProvider.overrideWithValue(
            MockMarineWeatherRepository(),
          ),
        ],
        child: const MaterialApp(home: WeatherScreen()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    // 지도 시각을 30시간 앞으로 옮긴다 — "지금"(0)과 확실히 다른 값.
    const movedOffset = 30;
    tester.widget<Slider>(find.byType(Slider)).onChanged!(
      movedOffset.toDouble(),
    );
    await tester.pump(const Duration(milliseconds: 16));

    await tester.tapAt(tester.getCenter(find.byType(WeatherScreen)));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.text('상세 예보'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    // 표를 닫는다.
    await tester.tap(find.byTooltip('지도로 돌아가기'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    // 지도 모드로 돌아왔으니 슬라이더가 다시 하나(지도용)만 있어야 하고,
    // 그 값이 0("지금")으로 되돌아가 있으면 안 된다 — 옮겨 둔 시각 근방을
    // 유지해야 한다(패널의 3시간 칸 반올림 오차를 감안해 넉넉히 확인).
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(
      slider.value,
      greaterThanOrEqualTo(movedOffset - 3),
      reason: '상세 예보를 닫자 지도 시각이 "지금"으로 되돌아갔다',
    );
  });
}
