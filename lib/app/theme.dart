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

/// 홈 상단·물때 카드 등 "남색 박스"에 쓰는 테마 연동 딥 컬러 2단계.
/// 현재 스킨(시드) 색상을 따르고, 다크 모드에서는 더 어둡게 낮춘다 —
/// 흰 글씨 대비를 유지하도록 명도를 낮게 고정한다.
List<Color> deepThemeColors(ColorScheme scheme) {
  final hsl = HSLColor.fromColor(scheme.primary);
  final dark = scheme.brightness == Brightness.dark;
  final sat = hsl.saturation.clamp(0.35, 1.0);
  final l1 = dark ? 0.15 : 0.26;
  final l2 = dark ? 0.09 : 0.17;
  return [
    hsl.withSaturation(sat).withLightness(l1).toColor(),
    hsl.withSaturation(sat).withLightness(l2).toColor(),
  ];
}
