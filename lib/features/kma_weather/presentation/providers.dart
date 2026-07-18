import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/storage/cache_store.dart';
import '../../locations/data/models/sea_location.dart';
import '../data/models/kma_forecast.dart';
import '../data/models/land_weather.dart';
import '../data/repositories/caching_kma_weather_repository.dart';
import '../data/repositories/caching_land_weather_repository.dart';
import '../data/repositories/data_go_kr_kma_repository.dart';
import '../data/repositories/kma_weather_repository.dart';
import '../data/repositories/land_weather_repository.dart';
import '../data/repositories/mock_kma_weather_repository.dart';
import '../data/repositories/mock_land_weather_repository.dart';
import '../data/repositories/open_meteo_land_repository.dart';
import '../data/weather_code.dart';

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

/// 육상 날씨(Open-Meteo) 리포지토리 주입 지점. 전 세계·키 불필요·16일.
/// 성공 시 캐시, 실패 시 캐시 → 합성 데이터 폴백.
final landWeatherRepositoryProvider = Provider<LandWeatherRepository>((ref) {
  final cachedReal = CachingLandWeatherRepository(
    inner: OpenMeteoLandWeatherRepository(),
    cache: ref.watch(cacheStoreProvider),
  );
  return LandWeatherRepository.withFallback(
    primary: cachedReal,
    fallback: MockLandWeatherRepository(),
  );
});

/// 날씨 예보 탭이 쓰는 최종 provider.
///
/// 뼈대는 Open-Meteo(15일 + 24시간 + 부가정보)이고, **기상청 단기예보가
/// 조회되면 근일(약 3일) 시간별 기온·날씨를 기상청 값으로 덮어쓴다**(기상청 우선).
/// 기상청 키가 없거나 실패하면 Open-Meteo 값을 그대로 쓴다.
final weatherForecastProvider =
    FutureProvider.family<WeatherForecast, SeaLocation>((ref, location) async {
      final base = await ref
          .watch(landWeatherRepositoryProvider)
          .fetchForecast(location);
      if (Env.dataGoKrApiKey.isEmpty) return base;
      try {
        final kma = await ref
            .watch(kmaWeatherRepositoryProvider)
            .fetchForecast(location);
        return _overlayKma(base, kma);
      } catch (_) {
        return base; // 기상청 실패 시 Open-Meteo 값 유지.
      }
    });

/// 기상청 시간별(기온·하늘/강수형태)을 Open-Meteo 뼈대의 같은 시각에 덮어쓴다.
WeatherForecast _overlayKma(WeatherForecast base, KmaForecast kma) {
  final byHour = <DateTime, KmaHourly>{
    for (final h in kma.hourly)
      DateTime(h.time.year, h.time.month, h.time.day, h.time.hour): h,
  };
  if (byHour.isEmpty) return base;

  final merged = [
    for (final h in base.hourly)
      if (byHour[DateTime(h.time.year, h.time.month, h.time.day, h.time.hour)]
          case final k?)
        h.copyWith(
          tempC: k.tempC,
          weatherCode: kmaToWmo(sky: k.skyCode, pty: k.ptyCode),
        )
      else
        h,
  ];

  // 현재값도 첫 기상청 시각과 맞으면 덮어쓴다.
  final nowKey = DateTime.now();
  final nowHour = DateTime(nowKey.year, nowKey.month, nowKey.day, nowKey.hour);
  final kNow = byHour[nowHour];
  final now = kNow == null
      ? base.now
      : WeatherNow(
          tempC: kNow.tempC,
          weatherCode: kmaToWmo(sky: kNow.skyCode, pty: kNow.ptyCode),
          humidityPct: kNow.humidityPercent,
          windSpeedMs: kNow.windSpeedMs,
          windGustMs: base.now.windGustMs,
          windDirDeg: base.now.windDirDeg,
          uvIndex: base.now.uvIndex,
          visibilityKm: base.now.visibilityKm,
          feelsLikeC: base.now.feelsLikeC,
        );

  return WeatherForecast(
    locationId: base.locationId,
    now: now,
    hourly: merged,
    daily: base.daily,
    air: base.air,
    nowcast: base.nowcast,
  );
}
