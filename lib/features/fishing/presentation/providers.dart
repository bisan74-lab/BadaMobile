import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/storage/cache_store.dart';
import '../../../core/storage/prefs.dart';
import '../../locations/data/models/sea_location.dart';
import '../data/models/fishing_index.dart';
import '../data/repositories/caching_fishing_repository.dart';
import '../data/repositories/data_go_kr_fishing_repository.dart';
import '../data/repositories/fishing_repository.dart';
import '../data/repositories/mock_fishing_repository.dart';

/// 낚시지수 리포지토리 주입 지점.
///
/// data.go.kr 인증키가 주입되면 실데이터(가장 가까운 포인트의 어종별 지수)를
/// 사용한다. 실데이터는 성공 시 로컬에 캐시되고(FR-11), 네트워크 실패 시
/// 캐시 → 그래도 없으면 합성 데이터로 폴백한다. 키가 없으면 합성 데이터 사용.
final fishingRepositoryProvider = Provider<FishingRepository>((ref) {
  final mock = MockFishingRepository();
  if (Env.dataGoKrApiKey.isEmpty) return mock;
  final cachedReal = CachingFishingRepository(
    inner: DataGoKrFishingRepository(),
    cache: ref.watch(cacheStoreProvider),
  );
  return FishingRepository.withFallback(primary: cachedReal, fallback: mock);
});

final fishingForecastProvider =
    FutureProvider.family<FishingForecast, SeaLocation>((ref, location) {
      return ref.watch(fishingRepositoryProvider).fetchForecast(location);
    });

/// 홈에 표시할 대표 어종(최대 3종). 이름을 눌러 후보 어종으로 바꿀 수 있고,
/// 선택은 SharedPreferences에 영속화된다.
class FishingSpeciesNotifier extends Notifier<List<String>> {
  static const _prefsKey = 'home_fishing_species';
  static const _maxCount = 3;

  @override
  List<String> build() {
    final saved = ref.read(sharedPreferencesProvider).getStringList(_prefsKey);
    final list = (saved == null || saved.isEmpty)
        ? defaultFishingSpecies
        : saved.where(fishingSpeciesCatalog.contains).toList();
    return list.isEmpty ? defaultFishingSpecies : list;
  }

  /// [slot]번째(0~2) 어종을 [species]로 바꾼다. 중복이면 무시.
  void setAt(int slot, String species) {
    if (!fishingSpeciesCatalog.contains(species)) return;
    final next = [...state];
    while (next.length <= slot && next.length < _maxCount) {
      next.add(species);
    }
    if (slot < next.length) next[slot] = species;
    // 중복 제거(순서 유지).
    final seen = <String>{};
    final deduped = [
      for (final s in next)
        if (seen.add(s)) s,
    ];
    state = deduped;
    ref.read(sharedPreferencesProvider).setStringList(_prefsKey, deduped);
  }
}

final fishingSpeciesProvider =
    NotifierProvider<FishingSpeciesNotifier, List<String>>(
      FishingSpeciesNotifier.new,
    );
