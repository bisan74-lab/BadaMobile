import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/cache_store.dart';
import '../../locations/data/models/sea_location.dart';
import '../data/models/marine_weather.dart';
import '../data/repositories/caching_marine_weather_repository.dart';
import '../data/repositories/marine_weather_repository.dart';
import '../data/repositories/mock_marine_weather_repository.dart';
import '../data/repositories/open_meteo_marine_repository.dart';

/// 해양 기상 리포지토리 주입 지점.
///
/// 기본: Open-Meteo 실데이터(16일). 성공 시 로컬에 캐시되고(FR-11),
/// 네트워크 실패 시 캐시 → 그래도 없으면 합성 데이터로 폴백한다.
/// 테스트에서는 이 provider를 override해 목을 직접 주입한다.
final marineWeatherRepositoryProvider = Provider<MarineWeatherRepository>((
  ref,
) {
  final cachedReal = CachingMarineWeatherRepository(
    inner: OpenMeteoMarineRepository(),
    cache: ref.watch(cacheStoreProvider),
  );
  return FallbackMarineWeatherRepository(
    primary: cachedReal,
    fallback: MockMarineWeatherRepository(),
  );
});

final marineForecastProvider =
    FutureProvider.family<MarineForecast, SeaLocation>((ref, location) {
      return ref.watch(marineWeatherRepositoryProvider).fetchForecast(location);
    });

/// 홈 화면의 4주(과거 2주~미래 2주) 날짜 이동용 예보.
const int homeForecastPastDays = 14;
const int homeForecastFutureDays = 14;

final homeMarineForecastProvider =
    FutureProvider.family<MarineForecast, SeaLocation>((ref, location) {
      return ref
          .watch(marineWeatherRepositoryProvider)
          .fetchForecast(
            location,
            hours: (homeForecastPastDays + homeForecastFutureDays) * 24,
            pastDays: homeForecastPastDays,
          );
    });
