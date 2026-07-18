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
