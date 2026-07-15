import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../locations/data/models/sea_location.dart';
import '../data/models/marine_weather.dart';
import '../data/repositories/marine_weather_repository.dart';
import '../data/repositories/mock_marine_weather_repository.dart';

/// 해양 기상 리포지토리 주입 지점. 실 API 연동 시 여기서 구현체만 교체한다.
final marineWeatherRepositoryProvider = Provider<MarineWeatherRepository>(
  (ref) => MockMarineWeatherRepository(),
);

final marineForecastProvider =
    FutureProvider.family<MarineForecast, SeaLocation>((ref, location) {
      return ref.watch(marineWeatherRepositoryProvider).fetchForecast(location);
    });
