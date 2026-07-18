import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/storage/cache_store.dart';
import '../../locations/data/models/sea_location.dart';
import '../data/models/kma_forecast.dart';
import '../data/repositories/caching_kma_weather_repository.dart';
import '../data/repositories/data_go_kr_kma_repository.dart';
import '../data/repositories/kma_weather_repository.dart';
import '../data/repositories/mock_kma_weather_repository.dart';

/// 기상청 단기예보 리포지토리 주입 지점. data.go.kr 인증키가 주입되면
/// (--dart-define=DATA_GO_KR_API_KEY=...) 실데이터를 쓴다. 실데이터는 성공
/// 시 로컬에 캐시되고, 실패 시 캐시 → 그래도 없으면 합성 데이터로 폴백한다.
final kmaWeatherRepositoryProvider = Provider<KmaWeatherRepository>((ref) {
  final mock = MockKmaWeatherRepository();
  if (Env.dataGoKrApiKey.isEmpty) return mock;
  final cachedReal = CachingKmaWeatherRepository(
    inner: DataGoKrKmaRepository(),
    cache: ref.watch(cacheStoreProvider),
  );
  return KmaWeatherRepository.withFallback(primary: cachedReal, fallback: mock);
});

final kmaForecastProvider = FutureProvider.family<KmaForecast, SeaLocation>((
  ref,
  location,
) {
  return ref.watch(kmaWeatherRepositoryProvider).fetchForecast(location);
});
