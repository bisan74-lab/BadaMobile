import 'package:bada_mobile/app/app.dart';
import 'package:bada_mobile/core/remote_config/app_gate_repository.dart';
import 'package:bada_mobile/core/remote_config/app_gate_provider.dart';
import 'package:bada_mobile/core/storage/prefs.dart';
import 'package:bada_mobile/features/weather/data/repositories/mock_marine_weather_repository.dart';
import 'package:bada_mobile/features/weather/presentation/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
      // 실 네트워크 호출 없이 항상 "강제 업데이트 아님"으로 응답하게 한다.
      appGateRepositoryProvider.overrideWithValue(
        AppGateRepository(
          client: MockClient((_) async => http.Response('{}', 200)),
        ),
      ),
    ],
    child: const BadaMobileApp(),
  );
}

void main() {
  testWidgets('앱이 렌더링되고 5개 탭이 보인다', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    expect(find.text('홈'), findsOneWidget);
    expect(find.text('날씨'), findsOneWidget);
    expect(find.text('물때'), findsOneWidget);
    expect(find.text('Windy'), findsOneWidget);
    expect(find.text('설정'), findsOneWidget);
    expect(find.text('바다 윈디'), findsOneWidget);
  });

  testWidgets('물때 탭으로 이동하면 만조/간조 목록이 보인다', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('물때'));
    await tester.pumpAndSettle();

    // 제목은 이제 지역명 없이 "물때"만, 지역은 우측 상단 선택 버튼에 표시된다.
    expect(find.widgetWithText(AppBar, '물때'), findsOneWidget);
    expect(find.textContaining('만조 '), findsWidgets);
    expect(find.textContaining('간조 '), findsWidgets);
  });

  testWidgets('우측 상단 지역 선택 버튼으로 지점을 바꿀 수 있다', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    // 홈 탭 AppBar 우측의 지역 선택 버튼(RegionSelectorAction)을 탭한다.
    await tester.tap(find.byIcon(Icons.edit_location_alt_outlined).first);
    await tester.pumpAndSettle();

    // 지역 선택 바텀시트에서 다른 지점을 스크롤로 찾아 선택한다.
    await tester.scrollUntilVisible(
      find.text('부산(영도)'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .last,
    );
    expect(find.text('부산(영도)'), findsOneWidget);
  });

  testWidgets('설정 탭에 템플릿/정보가 보인다', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();

    // 템플릿(펼침) + 그 아래 정보 항목이 한 화면에 나열된다.
    expect(find.text('템플릿'), findsOneWidget);
    expect(find.text('앱 테마'), findsOneWidget);
    expect(find.text('오류신고 및 사업제휴 문의'), findsOneWidget);
  });
}
