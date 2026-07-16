import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/storage/cache_store.dart';
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
