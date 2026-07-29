import 'package:bada_mobile/app/app.dart';
import 'package:bada_mobile/core/remote_config/app_gate_repository.dart';
import 'package:bada_mobile/core/remote_config/app_gate_provider.dart';
import 'package:bada_mobile/core/storage/prefs.dart';
import 'package:bada_mobile/features/weather/data/repositories/mock_marine_weather_repository.dart';
import 'package:bada_mobile/features/weather/data/repositories/mock_wind_field_repository.dart';
import 'package:bada_mobile/features/weather/presentation/providers.dart';
import 'package:bada_mobile/features/weather/presentation/wind_field_providers.dart';
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
      // 실 리포지토리는 HTTP 실패 시 재시도 지연 타이머를 쓰므로(테스트에서
      // pending timer로 실패) 바람장도 목으로 대체한다.
      windFieldRepositoryProvider.overrideWithValue(MockWindFieldRepository()),
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
  testWidgets('앱이 렌더링되고 오른쪽 3개 탭 레일이 보인다', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    // 하단 바 없이 오른쪽 세로 아이콘 레일: 물때날씨(선택)/Windy/설정.
    expect(find.byIcon(Icons.waves), findsOneWidget); // 선택된 물때날씨 탭
    expect(find.text('물때날씨'), findsOneWidget);
    expect(find.byIcon(Icons.air_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('첫 화면(물때&날씨)에 만조/간조와 광고 자리 소개가 보인다', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, '물때 & 날씨'), findsOneWidget);
    expect(find.textContaining('만조 '), findsWidgets);
    expect(find.textContaining('간조 '), findsWidgets);
    // 하단 광고 자리(앱 소개 박스)와 오른쪽 메뉴 항목(물때 복귀 버튼 포함).
    expect(find.text('바다윈디'), findsOneWidget);
    expect(find.text('물때'), findsOneWidget);
    expect(find.text('낚시정보'), findsOneWidget);
    expect(find.text('물때달력'), findsOneWidget);
  });

  testWidgets('다른 패널을 열었다가 미니 메뉴 물때로 타임라인에 돌아온다', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    // 물때달력 패널을 연 뒤(타임라인의 만조/간조 표기가 사라진다) —
    // 좁은 테스트 뷰포트에선 미니 메뉴가 스크롤되므로 먼저 드러낸다.
    await tester.ensureVisible(find.text('물때달력'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('물때달력'));
    await tester.pumpAndSettle();
    expect(find.text('일'), findsOneWidget); // 달력 요일 헤더

    // '물때' 버튼으로 만조·간조 타임라인에 명시적으로 복귀한다.
    await tester.ensureVisible(find.text('물때'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('물때'));
    await tester.pumpAndSettle();
    expect(find.textContaining('만조 '), findsWidgets);
  });

  testWidgets('오른쪽 메뉴 물때달력을 열면 달력 팝업이 뜬다', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    // 좁은 테스트 뷰포트에선 미니 메뉴가 스크롤되므로 먼저 드러낸다.
    await tester.ensureVisible(find.text('물때달력'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('물때달력'));
    await tester.pumpAndSettle();

    // 요일 헤더가 보이면 달력이 열린 것.
    expect(find.text('일'), findsOneWidget);
    expect(find.text('토'), findsOneWidget);
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

  testWidgets('지역 선택 시트의 해역 칩으로 목록을 좁힐 수 있다', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_location_alt_outlined).first);
    await tester.pumpAndSettle();

    // '동해' 칩을 누르면 동해 지점만 남는다(서해 목포는 사라진다).
    await tester.tap(find.widgetWithText(FilterChip, '동해'));
    await tester.pumpAndSettle();
    expect(find.text('감포(경주)'), findsOneWidget);
    expect(find.text('목포'), findsNothing);

    // '전체'로 돌아오면 다시 모든 해역이 보인다.
    await tester.tap(find.widgetWithText(FilterChip, '전체'));
    await tester.pumpAndSettle();
    expect(find.text('가로림만(서산)'), findsOneWidget);
  });

  testWidgets('설정 탭에 템플릿/정보가 보인다', (tester) async {
    await tester.pumpWidget(await buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    // 템플릿(펼침) + 데이터 정확도 + 하단 광고 자리.
    expect(find.text('템플릿'), findsOneWidget);
    expect(find.text('앱 테마'), findsOneWidget);
    expect(find.text('데이터 출처와 정확도'), findsOneWidget);
    expect(find.text('바다윈디'), findsOneWidget); // 하단 광고 자리(고정)

    // 정보 항목은 아래로 스크롤해야 보인다(새 섹션 추가로 길어짐).
    await tester.scrollUntilVisible(
      find.text('오류신고 및 사업제휴 문의'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('오류신고 및 사업제휴 문의'), findsOneWidget);
  });
}
