import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/remote_config/app_gate_provider.dart';
import '../core/storage/prefs.dart';
import '../features/locations/presentation/providers.dart';
import '../features/settings/presentation/providers.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/tide/presentation/tide_screen.dart';
import '../features/weather/presentation/weather_screen.dart';
import 'app_tab_provider.dart';
import 'force_upgrade_screen.dart';
import 'theme.dart';

/// 앱 진입점. `appGateProvider`가 강제 업데이트 상태(`forceUpgrade: true`)를
/// 돌려주면 [AppShell] 대신 [ForceUpgradeScreen]을 띄워 실행을 막는다 —
/// 무료 배포본을 나중에 광고 버전으로 전환할 때, 앱 재배포 없이
/// `remote_config/app_gate.json`의 값만 바꾸면 모든 설치 기기에 적용된다.
/// 설정 확인이 안 되면(오프라인 등) 항상 앱을 정상 실행한다.
class BadaMobileApp extends ConsumerWidget {
  const BadaMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gateAsync = ref.watch(appGateProvider);
    final skin = ref.watch(skinProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: '바다 윈디',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(skin.seed),
      darkTheme: buildDarkTheme(skin.seed),
      themeMode: themeMode,
      home: gateAsync.when(
        data: (gate) => gate.forceUpgrade
            ? ForceUpgradeScreen(config: gate)
            : const AppShell(),
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => const AppShell(),
      ),
    );
  }
}

/// 하단 탭 기반 앱 셸: 물때&날씨 / Windy / 설정.
/// 낚시정보(구 홈)·날씨 상세는 물때&날씨 화면의 오른쪽 메뉴에서 푸시로 연다.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _screens = [TideScreen(), WeatherScreen(), SettingsScreen()];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLocation());
  }

  /// 앱 시작 시 위치 처리. **현재 위치는 날씨 탭에만** 적용한다(홈/물때/Windy는
  /// 공용 지역을 그대로 쓰며 현재 위치와 연동하지 않는다). 날씨 탭에 저장된
  /// 위치가 있으면 그 위치로 시작하고, 없는 첫 실행이면 위치 권한을 요청해
  /// 현재 위치로 설정한다. 권한 거부·실패 시엔 기본 위치를 유지한다.
  Future<void> _initLocation() async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (prefs.getString('weather_location') != null) return;
    try {
      final loc = await resolveCurrentLocation();
      if (!mounted) return;
      ref.read(weatherLocationProvider.notifier).select(loc);
    } catch (_) {
      // 권한 거부/위치 서비스 꺼짐 등 — 기본 위치로 조용히 시작한다.
    }
  }

  @override
  Widget build(BuildContext context) {
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

/// 우하단 세로 스택의 가로형 필 탭 내비게이션(하단 바 대체, Windy 레일과
/// 같은 위치). 아이콘+라벨의 긴 필 모양이라 그래프 위 미니 메뉴와 확실히
/// 구분된다. 전체 투명도 50%.
class _SideNavRail extends StatelessWidget {
  const _SideNavRail({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _icons = <(IconData, IconData, String)>[
    (Icons.waves_outlined, Icons.waves, '물때&날씨'),
    (Icons.air_outlined, Icons.air, 'Windy'),
    (Icons.settings_outlined, Icons.settings, '설정'),
  ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Opacity(
      opacity: 0.5,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _icons.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Material(
                color: i == index ? primary : Colors.black87,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => onSelect(i),
                  child: Container(
                    width: 108,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          i == index ? _icons[i].$2 : _icons[i].$1,
                          size: 17,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            _icons[i].$3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
