import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/storage/cache_store.dart';
import '../../locations/data/models/sea_location.dart';
import '../data/models/tide_data.dart';
import '../data/repositories/caching_tide_repository.dart';
import '../data/repositories/data_go_kr_tide_obs_repository.dart';
import '../data/repositories/data_go_kr_tide_repository.dart';
import '../data/repositories/mock_tide_repository.dart';
import '../data/repositories/tide_repository.dart';

/// 조석 리포지토리 주입 지점.
///
/// data.go.kr 인증키가 주입되면(--dart-define=DATA_GO_KR_API_KEY=...) 실데이터
/// 체인을 쓴다: **조위관측소 실측·예측 조위(시계열)** → 실패 시 **조석예보
/// (고저조)** → 그래도 실패 시 **합성 데이터**. 두 실API 모두 성공 시 로컬에
/// 캐시되고(FR-11), 키가 없으면(개발/테스트 기본) 합성 데이터를 쓴다.
///
/// 실측·예측 조위를 1순위로 두는 이유: 1시간 간격 연속 곡선을 주므로 조위
/// 그래프가 매끄럽고, 극값(만조/간조)도 포물선 보간으로 시분까지 정밀하다.
/// 고저조 API는 극값만 주지만 실측·예측이 막힐 때의 백업으로 남겨 둔다.
final tideRepositoryProvider = Provider<TideRepository>((ref) {
  final mock = MockTideRepository();
  if (Env.dataGoKrApiKey.isEmpty) return mock;
  final cache = ref.watch(cacheStoreProvider);
  final obsSeries = CachingTideRepository(
    inner: DataGoKrTideObsRepository(),
    cache: cache,
  );
  final hghLw = CachingTideRepository(
    inner: DataGoKrTideRepository(),
    cache: cache,
  );
  return TideRepository.withFallback(
    primary: obsSeries,
    fallback: TideRepository.withFallback(primary: hghLw, fallback: mock),
  );
});

typedef TideQuery = ({SeaLocation location, DateTime date});

final tideDayProvider = FutureProvider.family<TideDay, TideQuery>((ref, query) {
  return ref
      .watch(tideRepositoryProvider)
      .fetchTideDay(query.location, query.date);
});
