import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/storage/cache_store.dart';
import '../../locations/data/models/sea_location.dart';
import '../data/models/tide_data.dart';
import '../data/repositories/caching_tide_repository.dart';
import '../data/repositories/data_go_kr_tide_repository.dart';
import '../data/repositories/mock_tide_repository.dart';
import '../data/repositories/tide_repository.dart';

/// 조석 리포지토리 주입 지점.
///
/// data.go.kr 인증키가 주입되면(--dart-define=DATA_GO_KR_API_KEY=...)
/// 조석예보(고저조) 실데이터를 사용한다. 실데이터는 성공 시 로컬에 캐시되고
/// (FR-11), 네트워크 실패 시 캐시 → 그래도 없으면 합성 데이터로 폴백한다.
/// 키가 없으면(개발/테스트 기본) 합성 데이터를 쓴다.
final tideRepositoryProvider = Provider<TideRepository>((ref) {
  final mock = MockTideRepository();
  if (Env.dataGoKrApiKey.isEmpty) return mock;
  final cachedReal = CachingTideRepository(
    inner: DataGoKrTideRepository(),
    cache: ref.watch(cacheStoreProvider),
  );
  return TideRepository.withFallback(primary: cachedReal, fallback: mock);
});

typedef TideQuery = ({SeaLocation location, DateTime date});

final tideDayProvider = FutureProvider.family<TideDay, TideQuery>((ref, query) {
  return ref
      .watch(tideRepositoryProvider)
      .fetchTideDay(query.location, query.date);
});
