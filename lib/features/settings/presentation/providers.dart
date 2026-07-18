import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/storage/prefs.dart';

/// 현재 선택된 앱 스킨(시드 색). 설정 > 템플릿에서 바꾸며,
/// SharedPreferences에 저장되어 앱 재시작 후에도 유지된다.
class SkinNotifier extends Notifier<AppSkin> {
  static const _prefsKey = 'app_skin_id';

  @override
  AppSkin build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_prefsKey);
    return skinById(saved);
  }

  void select(AppSkin skin) {
    state = skin;
    ref.read(sharedPreferencesProvider).setString(_prefsKey, skin.id);
  }
}

final skinProvider = NotifierProvider<SkinNotifier, AppSkin>(SkinNotifier.new);

/// 밝기 모드(시스템/라이트/다크). 앱 전체 [MaterialApp.themeMode]에 반영된다.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _prefsKey = 'theme_mode';

  @override
  ThemeMode build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_prefsKey);
    return ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
  }

  void select(ThemeMode mode) {
    state = mode;
    ref.read(sharedPreferencesProvider).setString(_prefsKey, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// 배경 그래픽(직접 그린 바다 일러스트) 표시 여부. 물때 타임라인 등
/// 장식 배경에 반영된다.
class BackdropNotifier extends Notifier<bool> {
  static const _prefsKey = 'sea_backdrop_enabled';

  @override
  bool build() =>
      ref.read(sharedPreferencesProvider).getBool(_prefsKey) ?? true;

  void set(bool value) {
    state = value;
    ref.read(sharedPreferencesProvider).setBool(_prefsKey, value);
  }
}

final backdropEnabledProvider = NotifierProvider<BackdropNotifier, bool>(
  BackdropNotifier.new,
);
