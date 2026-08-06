import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/remote_config/app_gate_provider.dart';
import '../core/widgets/nav_chip.dart';
import '../features/settings/app_info.dart';
import '../features/settings/presentation/providers.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/tide/presentation/tide_screen.dart';
import '../features/weather/presentation/weather_screen.dart';
import 'app_tab_provider.dart';
import 'force_upgrade_screen.dart';
import 'theme.dart';

/// **앱 전체 글자 배율 상한.**
///
/// 시스템 글자 크기를 크게 하면 앱의 모든 글자가 그만큼 커진다. 이 앱은
/// 물때표·상세예보 표·설정처럼 **한 화면에 많은 값을 촘촘히 담는 화면**이
/// 많아, 배율이 이보다 오르면 글자가 서로 겹치거나 잘려 오히려 읽을 수
/// 없게 된다(2026-08-06 사용자 제보 스크린샷 3종: 오른쪽 메뉴 겹침, 설정
/// 화면 줄바꿈 붕괴, 상세예보 표 잘림).
///
/// 화면마다 따로 대응하는 것도 시도했지만(메뉴만 세 번 고쳤다) 같은 종류가
/// 앱 곳곳에 있어 끝이 없었다. 여기서 한 번 막는 것이 실무에서 흔한 해법이고
/// 효과도 확실하다.
///
/// **대가는 분명하다** — 사용자의 접근성 설정을 일부 무시한다. 그래서 값을
/// 함부로 낮추지 말 것(1.3은 "본문이 눈에 띄게 커지지만 표는 아직 버티는"
/// 선이다). 더 크게 보고 싶은 사용자를 위해서는 앱 안에 글자 크기 설정을
/// 따로 두는 편이 맞다.
const double kMaxTextScale = 1.3;

/// [kMaxTextScale]을 적용한다. `MaterialApp.builder`에 그대로 넘기면 앱 안
/// 모든 화면에 걸린다. **테스트 하네스도 같은 함수를 써야** 실제 화면과 같은
/// 조건으로 검사된다.
Widget clampAppTextScale(BuildContext context, Widget? child) {
  final mq = MediaQuery.of(context);
  return MediaQuery(
    data: mq.copyWith(
      textScaler: mq.textScaler.clamp(maxScaleFactor: kMaxTextScale),
    ),
    child: child ?? const SizedBox.shrink(),
  );
}

/// 앱 진입점. `appGateProvider`의 설정이 **지금 버전을 막아야 한다고**
/// 하면([AppGateConfig.blocks]) [AppShell] 대신 [ForceUpgradeScreen]을 띄워
/// 실행을 막는다.
///
/// 새 버전을 Play에 올린 뒤 공개 데이터 저장소 `app_gate.json`의
/// `minSupportedVersion`을 그 버전으로 올리면, **앱 재배포 없이** 구버전을
/// 쓰던 기기가 다음 실행부터 업데이트 안내 화면만 보게 된다.
///
/// **게이트를 기다리지 않는다** — `appGateProvider`가 지난 실행에서 캐시해 둔
/// 설정을 곧바로 주고 새 설정은 백그라운드로 받는다. 그래서 여기엔 로딩
/// 상태가 없다(예전에는 이 자리에서 최대 5초 동안 스피너만 돌았다).
/// 설정 확인이 안 되면(오프라인 등) 항상 앱을 정상 실행한다.
class BadaMobileApp extends ConsumerWidget {
  const BadaMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gate = ref.watch(appGateProvider);
    final skin = ref.watch(skinProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: '바다윈디',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(skin.seed),
      darkTheme: buildDarkTheme(skin.seed),
      themeMode: themeMode,
      // 모든 화면에 한 번에 적용된다([kMaxTextScale] 참고).
      builder: clampAppTextScale,
      home: gate.blocks(AppInfo.appVersion)
          ? ForceUpgradeScreen(config: gate)
          : const AppShell(),
    );
  }
}

/// 우하단 탭 레일의 라벨. 물때 화면이 겹침을 피하려고 같은 목록으로 높이를
/// 계산한다([sideNavRailHeight]).
const sideNavRailLabels = <String>['물때날씨', '바람지도', '설정'];

/// 우하단 탭 레일이 세로로 차지하는 높이(글자 배율 반영).
double sideNavRailHeight(BuildContext context) =>
    navChipsHeight(context, sideNavRailLabels);

/// 하단 탭 기반 앱 셸: 물때&날씨 / Windy / 설정.
/// 낚시정보(구 홈)·날씨 상세는 물때&날씨 화면의 오른쪽 메뉴에서 푸시로 연다.
///
/// 위치 권한은 어디서도 요청하지 않는다 — 날씨 탭도 저장된(또는 기본) 지역을
/// 그대로 쓰고, 지역 변경은 지역 선택 시트의 목록·지명 검색으로만 한다.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _screens = [TideScreen(), WeatherScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(appTabIndexProvider);
    // 하단 바 없이 모든 탭에서 오른쪽 세로 아이콘 내비게이션을 쓴다(사용자
    // 요구). Windy 탭은 자기 화면 안에 전용 레일이 있으므로 중복해서 띄우지
    // 않는다.
    final onWindy = index == windyTabIndex;
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: index,
            // 화면 밖 탭(특히 애니메이션이 있는 Windy 탭)의 Ticker를 꺼서
            // 불필요한 리빌드와 배터리 소모, pumpAndSettle 무한대기를 막는다.
            children: [
              for (var i = 0; i < _screens.length; i++)
                TickerMode(enabled: i == index, child: _screens[i]),
            ],
          ),
          if (!onWindy)
            // Windy 탭 레일과 같은 위치(우하단)에 가로로 긴 필 버튼으로
            // 표시한다 — 다른(미니) 메뉴들과 구분되는 스타일(사용자 요구).
            Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 88),
                child: _SideNavRail(
                  key: const Key('app_nav_rail'),
                  index: index,
                  onSelect: (i) =>
                      ref.read(appTabIndexProvider.notifier).state = i,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 우하단 세로 탭 내비게이션(하단 바 대체). 물때 화면의 미니 메뉴와 같은
/// [NavChip]을 쓰고, 활성 탭은 강조색으로 채운다. 전체 투명도 50%.
///
/// **높이가 글자 배율에 따라 커진다.** 물때 화면 미니 메뉴가 이 레일과 겹치지
/// 않으려면 같은 계산([sideNavRailHeight])으로 자리를 비워 둬야 한다.
class _SideNavRail extends StatelessWidget {
  const _SideNavRail({super.key, required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _icons = <(IconData, IconData)>[
    // 물때&날씨 화면의 미니 메뉴에 '물때' 버튼이 생기면서, 같은 이름이
    // 두 개 되지 않게 탭 라벨은 '물때날씨'(물때&날씨 축약)로 구분한다.
    (Icons.waves_outlined, Icons.waves),
    (Icons.air_outlined, Icons.air),
    (Icons.settings_outlined, Icons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.5,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _icons.length; i++)
            NavChip(
              icon: i == index ? _icons[i].$2 : _icons[i].$1,
              label: sideNavRailLabels[i],
              selected: i == index,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}
