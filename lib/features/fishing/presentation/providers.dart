import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/storage/cache_store.dart';
import '../../../core/storage/prefs.dart';
import '../../locations/data/models/sea_location.dart';
import '../data/models/fishing_index.dart';
import '../data/models/jigging_estimate.dart';
import '../data/repositories/caching_fishing_repository.dart';
import '../data/repositories/data_go_kr_fishing_repository.dart';
import '../data/repositories/fishing_repository.dart';
import '../data/repositories/github_fishing_repository.dart';
import '../data/repositories/mock_fishing_repository.dart';

/// 낚시지수 리포지토리 주입 지점.
///
/// 체인은 **서버 파일 → data.go.kr 직접 호출 → 캐시 → 합성**이다.
///
/// 서버 파일(`fishing-data.yml`이 하루 한 번 올리는 약 20KB gz)을 먼저 쓴다 —
/// data.go.kr의 이 API는 한 쪽에 300건까지만 주므로 앱이 직접 받으면 6쪽을
/// 나눠 받아야 하고 6초쯤 걸린다(실측). 서버 파일을 못 받으면 예전처럼 직접
/// 호출하고, 그것도 실패하면 캐시 → 합성 데이터로 내려간다.
///
/// 인증키가 없으면 직접 호출 경로가 없으므로 서버 파일 → 합성으로 간다.
final fishingRepositoryProvider = Provider<FishingRepository>((ref) {
  final mock = MockFishingRepository();
  final cache = ref.watch(cacheStoreProvider);

  // 직접 호출 경로(키가 있을 때만). 성공하면 지역별로 캐시해 오프라인 대비.
  final direct = Env.dataGoKrApiKey.isEmpty
      ? mock
      : CachingFishingRepository(
          // 전국 하루치 원본은 리포지토리가 **날짜 단위로** 캐시한다.
          inner: DataGoKrFishingRepository(cache: cache),
          cache: cache,
        );

  final fromServer = GithubFishingRepository(direct: direct, cache: cache);
  return FishingRepository.withFallback(primary: fromServer, fallback: mock);
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
        : saved.where(allSelectableSpecies.contains).toList();
    return list.isEmpty ? defaultFishingSpecies : list;
  }

  /// [slot]번째(0~2) 어종을 [species]로 바꾼다. 중복이면 무시.
  void setAt(int slot, String species) {
    if (!allSelectableSpecies.contains(species)) return;
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

/// 물때&날씨 화면 낚시정보 패널의 어종 선택(최대 5종).
/// **비어 있으면 달별 제철 어종을 자동으로 쓴다**(기본 동작). 사용자가
/// 어종을 직접 고르면 SharedPreferences에 영속화되어 계절이 바뀌어도
/// 유지되고, "제철 어종(자동)"으로 되돌리면 다시 비워진다.
class TideFishingSpeciesNotifier extends Notifier<List<String>> {
  static const _prefsKey = 'tide_fishing_species';
  static const maxCount = 5;

  @override
  List<String> build() {
    final saved = ref.read(sharedPreferencesProvider).getStringList(_prefsKey);
    return (saved ?? const []).where(allSelectableSpecies.contains).toList();
  }

  /// [species]로 교체한다(카탈로그에 있는 어종만, 최대 [maxCount]종).
  /// 빈 목록을 넘기면 제철 어종 자동 모드로 돌아간다.
  void set(List<String> species) {
    final list = species
        .where(allSelectableSpecies.contains)
        .take(maxCount)
        .toList();
    state = list;
    ref.read(sharedPreferencesProvider).setStringList(_prefsKey, list);
  }
}

final tideFishingSpeciesProvider =
    NotifierProvider<TideFishingSpeciesNotifier, List<String>>(
      TideFishingSpeciesNotifier.new,
    );
