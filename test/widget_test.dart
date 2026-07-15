import 'package:bada_mobile/app/app.dart';
import 'package:bada_mobile/features/weather/data/repositories/mock_marine_weather_repository.dart';
import 'package:bada_mobile/features/weather/presentation/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 테스트에서는 실 API 대신 목 리포지토리를 주입한다.
Widget buildApp() => ProviderScope(
  overrides: [
    marineWeatherRepositoryProvider.overrideWithValue(
      MockMarineWeatherRepository(),
    ),
  ],
  child: const BadaMobileApp(),
);

void main() {
  testWidgets('앱이 렌더링되고 4개 탭이 보인다', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('홈'), findsOneWidget);
    expect(find.text('물때'), findsOneWidget);
    expect(find.text('날씨'), findsOneWidget);
    expect(find.text('지역'), findsOneWidget);
    expect(find.text('바다모바일'), findsOneWidget);
  });

  testWidgets('물때 탭으로 이동하면 만조/간조 목록이 보인다', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('물때'));
    await tester.pumpAndSettle();

    expect(find.textContaining('물때 · '), findsOneWidget);
    expect(find.text('만조'), findsWidgets);
    expect(find.text('간조'), findsWidgets);
  });

  testWidgets('지역 탭에서 지점을 선택할 수 있다', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('지역'));
    await tester.pumpAndSettle();

    expect(find.text('지역 선택'), findsOneWidget);
    expect(find.text('부산(영도)'), findsOneWidget);
  });
}
