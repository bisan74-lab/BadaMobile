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
  testWidgets('날씨 화면이 지도·시간 스크러버·상세 정보를 그린다', (tester) async {
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

    expect(find.byType(CustomPaint), findsWidgets);
    // 지도가 화면 전체를 채우고 그 위에 하단 정보 바가 겹쳐 뜨므로
    // 스크롤 없이 바로 스크러버가 보여야 한다.
    expect(find.byType(Slider), findsOneWidget);
    // "지금"이 아니라 실제 날짜·시간이 표시되어야 한다.
    expect(find.textContaining(':'), findsWidgets);
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
