import 'package:bada_mobile/app/app.dart';
import 'package:bada_mobile/core/storage/prefs.dart';
import 'package:bada_mobile/features/weather/data/repositories/mock_marine_weather_repository.dart';
import 'package:bada_mobile/features/weather/presentation/providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 테스트에서는 실 API 대신 목 리포지토리와 인메모리 prefs를 주입한다.
Future<Widget> buildApp() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      marineWeatherRepositoryProvider.overrideWithValue(
        MockMarineWeatherRepository(),
      ),
    ],
    child: const BadaMobileApp(),
  );
}

void main() {
  testWidgets('앱이 렌더링되고 4개 탭이 보인다', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    expect(find.text('홈'), findsOneWidget);
    expect(find.text('물때'), findsOneWidget);
    expect(find.text('날씨'), findsOneWidget);
    expect(find.text('지역'), findsOneWidget);
    expect(find.text('바다윈디'), findsOneWidget);
  });

  testWidgets('물때 탭으로 이동하면 만조/간조 목록이 보인다', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('물때'));
    await tester.pumpAndSettle();

    expect(find.textContaining('물때 · '), findsOneWidget);
    expect(find.textContaining('만조 '), findsWidgets);
    expect(find.textContaining('간조 '), findsWidgets);
  });

  testWidgets('지역 탭에서 지점을 선택할 수 있다', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('지역'));
    await tester.pumpAndSettle();

    expect(find.text('지역 선택'), findsOneWidget);
    // 지역 목록이 길어 화면 밖일 수 있으므로 스크롤하며 찾는다.
    await tester.scrollUntilVisible(
      find.text('부산(영도)'),
      200,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('부산(영도)'), findsOneWidget);
  });
}
