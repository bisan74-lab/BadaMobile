import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../locations/data/models/sea_location.dart';
import '../data/models/marine_weather.dart';
import '../data/repositories/marine_weather_repository.dart';
import '../data/repositories/mock_marine_weather_repository.dart';
import '../data/repositories/open_meteo_marine_repository.dart';

/// 해양 기상 리포지토리 주입 지점.
///
/// 기본: Open-Meteo 실데이터(16일), 네트워크 실패 시 합성 데이터로 폴백.
/// 테스트에서는 이 provider를 override해 목을 직접 주입한다.
final marineWeatherRepositoryProvider = Provider<MarineWeatherRepository>(
  (ref) => FallbackMarineWeatherRepository(
    primary: OpenMeteoMarineRepository(),
    fallback: MockMarineWeatherRepository(),
  ),
);

final marineForecastProvider =
    FutureProvider.family<MarineForecast, SeaLocation>((ref, location) {
      return ref.watch(marineWeatherRepositoryProvider).fetchForecast(location);
    });
