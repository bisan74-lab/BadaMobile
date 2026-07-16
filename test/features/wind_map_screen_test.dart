import 'package:bada_mobile/core/storage/prefs.dart';
import 'package:bada_mobile/features/weather/data/repositories/mock_wind_field_repository.dart';
import 'package:bada_mobile/features/weather/presentation/wind_field_providers.dart';
import 'package:bada_mobile/features/weather/presentation/wind_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 파티클 애니메이션은 계속 반복되는 Ticker를 쓰므로 pumpAndSettle은 쓰지 않고
  // pump()로 몇 프레임만 진행해 예외 없이 그려지는지 확인한다.
  testWidgets('바람 지도가 로딩 후 파티클 캔버스를 그린다', (tester) async {
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
        child: const MaterialApp(home: WindMapScreen()),
      ),
    );

    // 초기 로딩 표시.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(); // FutureProvider 완료
    await tester.pump(const Duration(milliseconds: 16)); // 첫 애니메이션 프레임
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.textContaining('기준'), findsOneWidget);
  });
}
