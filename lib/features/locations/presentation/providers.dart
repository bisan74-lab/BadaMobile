import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/prefs.dart';
import '../data/models/sea_location.dart';
import '../data/sample_locations.dart';

/// 전체 지점 목록. 추후 원격 목록/검색으로 대체.
final locationsProvider = Provider<List<SeaLocation>>((ref) => sampleLocations);

/// 현재 선택된 지점 — 홈/물때/날씨 화면이 모두 이 값을 따른다.
/// 선택은 SharedPreferences에 저장되어 앱 재시작 후에도 유지된다 (FR-10).
class SelectedLocationNotifier extends Notifier<SeaLocation> {
  static const _prefsKey = 'selected_location_id';

  @override
  SeaLocation build() {
    final all = ref.read(locationsProvider);
    final savedId = ref.read(sharedPreferencesProvider).getString(_prefsKey);
    return all.firstWhere((l) => l.id == savedId, orElse: () => all.first);
  }

  void select(SeaLocation location) {
    state = location;
    ref.read(sharedPreferencesProvider).setString(_prefsKey, location.id);
  }
}

final selectedLocationProvider =
    NotifierProvider<SelectedLocationNotifier, SeaLocation>(
      SelectedLocationNotifier.new,
    );

/// 즐겨찾기 지점 id 집합. SharedPreferences에 영속화된다 (FR-10).
class FavoritesNotifier extends Notifier<Set<String>> {
  static const _prefsKey = 'favorite_location_ids';

  @override
  Set<String> build() {
    final saved = ref.read(sharedPreferencesProvider).getStringList(_prefsKey);
    return (saved ?? const []).toSet();
  }

  void toggle(String id) {
    state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
    ref
        .read(sharedPreferencesProvider)
        .setStringList(_prefsKey, state.toList());
  }
}

final favoritesProvider = NotifierProvider<FavoritesNotifier, Set<String>>(
  FavoritesNotifier.new,
);
