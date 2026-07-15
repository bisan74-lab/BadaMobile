import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/sea_location.dart';
import '../data/sample_locations.dart';

/// 전체 지점 목록. 추후 원격 목록/검색으로 대체.
final locationsProvider = Provider<List<SeaLocation>>((ref) => sampleLocations);

/// 현재 선택된 지점 — 홈/물때/날씨 화면이 모두 이 값을 따른다.
final selectedLocationProvider = StateProvider<SeaLocation>(
  (ref) => sampleLocations.first,
);

/// 즐겨찾기 지점 id 집합. 추후 shared_preferences 등으로 영속화.
class FavoritesNotifier extends StateNotifier<Set<String>> {
  FavoritesNotifier() : super(const {});

  void toggle(String id) {
    state = state.contains(id) ? ({...state}..remove(id)) : {...state, id};
  }
}

final favoritesProvider = StateNotifierProvider<FavoritesNotifier, Set<String>>(
  (ref) => FavoritesNotifier(),
);
