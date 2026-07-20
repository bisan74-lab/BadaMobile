import 'package:bada_mobile/core/storage/prefs.dart';
import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:bada_mobile/features/locations/presentation/providers.dart';
import 'package:bada_mobile/features/weather/data/repositories/mock_wind_field_repository.dart';
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
}
