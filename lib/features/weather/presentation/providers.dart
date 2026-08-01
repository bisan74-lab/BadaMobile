import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/cache_store.dart';
import '../../locations/data/models/sea_location.dart';
import '../data/models/marine_weather.dart';
import '../data/repositories/caching_marine_weather_repository.dart';
import '../data/repositories/github_point_forecast_repository.dart';
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

/// 홈 화면·낚시정보 카드 전용 리포지토리 — **서버 파일 우선**.
///
/// 두 화면은 날짜별 대표값 하나씩만 쓰므로, 지역마다 Open-Meteo를 5번씩
/// 부르는 대신 서버가 3시간마다 모아 둔 파일 하나를 쓴다(지역 변경 시
/// 네트워크 없음). 파일에 없는 지역이나 다운로드 실패는 직접 호출로 폴백한다.
/// 상세 예보 화면([marineForecastProvider])은 너울·파력까지 필요해서 그대로
/// 직접 호출을 쓴다.
final pointForecastRepositoryProvider = Provider<MarineWeatherRepository>((
  ref,
) {
  return GithubPointForecastRepository(
    direct: ref.watch(marineWeatherRepositoryProvider),
    cache: ref.watch(cacheStoreProvider),
  );
});

final homeMarineForecastProvider =
    FutureProvider.family<MarineForecast, SeaLocation>((ref, location) {
      return ref
          .watch(pointForecastRepositoryProvider)
          .fetchForecast(
            location,
            hours: (homeForecastPastDays + homeForecastFutureDays) * 24,
            pastDays: homeForecastPastDays,
          );
    });
