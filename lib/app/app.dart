import 'package:flutter/material.dart';

import '../features/home/presentation/home_screen.dart';
import '../features/locations/presentation/locations_screen.dart';
import '../features/tide/presentation/tide_screen.dart';
import '../features/weather/presentation/weather_screen.dart';
import 'theme.dart';

class BadaMobileApp extends StatelessWidget {
  const BadaMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '바다윈디',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      home: const AppShell(),
    );
  }
}

/// 하단 탭 기반 앱 셸: 홈 / 물때 / 날씨 / 지역
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    TideScreen(),
    WeatherScreen(),
    LocationsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        // 화면 밖 탭(특히 애니메이션이 있는 날씨 탭)의 Ticker를 꺼서
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
            icon: Icon(Icons.waves_outlined),
            selectedIcon: Icon(Icons.waves),
            label: '물때',
          ),
          NavigationDestination(
            icon: Icon(Icons.air_outlined),
            selectedIcon: Icon(Icons.air),
            label: '날씨',
          ),
          NavigationDestination(
            icon: Icon(Icons.place_outlined),
            selectedIcon: Icon(Icons.place),
            label: '지역',
          ),
        ],
      ),
    );
  }
}
