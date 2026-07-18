import 'package:flutter/material.dart';

/// 설정 > 템플릿에서 고를 수 있는 앱 스킨(시드 색) 프리셋.
/// id는 SharedPreferences에 저장되므로 절대 바꾸지 말 것.
class AppSkin {
  const AppSkin({required this.id, required this.name, required this.seed});

  final String id;
  final String name;
  final Color seed;
}

const appSkins = <AppSkin>[
  AppSkin(id: 'ocean', name: '바다', seed: Color(0xFF0E6BA8)),
  AppSkin(id: 'sunset', name: '노을', seed: Color(0xFFE4572E)),
  AppSkin(id: 'forest', name: '숲', seed: Color(0xFF2E7D32)),
  AppSkin(id: 'grape', name: '포도', seed: Color(0xFF6A4C93)),
  AppSkin(id: 'graphite', name: '그래파이트', seed: Color(0xFF455A64)),
];

final defaultSkin = appSkins.first;

AppSkin skinById(String? id) =>
    appSkins.firstWhere((s) => s.id == id, orElse: () => defaultSkin);

ThemeData buildLightTheme([Color seed = _defaultSeed]) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: seed),
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}

ThemeData buildDarkTheme([Color seed = _defaultSeed]) {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
  );
}

const _defaultSeed = Color(0xFF0E6BA8); // 깊은 바다색
