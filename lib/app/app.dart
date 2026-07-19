import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/remote_config/app_gate_provider.dart';
import '../core/storage/prefs.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/kma_weather/presentation/kma_weather_screen.dart';
import '../features/locations/presentation/providers.dart';
import '../features/settings/presentation/providers.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/tide/presentation/tide_screen.dart';
import '../features/weather/presentation/weather_screen.dart';
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

/// 하단 탭 기반 앱 셸: 홈 / 날씨 / 물때 / Windy / 설정
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    KmaWeatherScreen(),
    TideScreen(),
    WeatherScreen(),
    SettingsScreen(),
  ];

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
    return Scaffold(
      body: IndexedStack(
        index: _index,
        // 화면 밖 탭(특히 애니메이션이 있는 Windy 탭)의 Ticker를 꺼서
        // 불필요한 리빌드와 배터리 소모, pumpAndSettle 무한대기를 막는다.
        children: [
          for (var i = 0; i < _screens.length; i++)
            TickerMode(enabled: i == _index, child: _screens[i]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '홈',
          ),
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: Icon(Icons.wb_sunny),
            label: '날씨',
          ),
          NavigationDestination(
            icon: Icon(Icons.waves_outlined),
            selectedIcon: Icon(Icons.waves),
            label: '물때',
          ),
          NavigationDestination(
            icon: Icon(Icons.air_outlined),
            selectedIcon: Icon(Icons.air),
            label: 'Windy',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
