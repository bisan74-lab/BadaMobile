import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/wind_field.dart';
import '../data/repositories/mock_wind_field_repository.dart';
import '../data/repositories/open_meteo_wind_field_repository.dart';
import '../data/repositories/wind_field_repository.dart';

final windFieldRepositoryProvider = Provider<WindFieldRepository>(
  (ref) => OpenMeteoWindFieldRepository(),
);

/// 현재 시점 바람장 스냅샷. 실패하면 합성 바람장으로 폴백한다.
final windFieldProvider = FutureProvider.autoDispose<WindField>((ref) async {
  final repo = ref.watch(windFieldRepositoryProvider);
  try {
    return await repo.fetchField();
  } catch (_) {
    return MockWindFieldRepository().fetchField();
  }
});

/// 시간 스크러버가 다룰 시계열 범위: 향후 2주(Open-Meteo 예보 한도 내).
const int windFieldSeriesHours = 24 * 14;

/// 2주 바람장 시계열 — 지도 화면의 시간 스크러버에 쓰인다.
/// 실패하면 합성 바람장 시계열로 폴백한다.
final windFieldSeriesProvider = FutureProvider.autoDispose<WindFieldSeries>((
  ref,
) async {
  final repo = ref.watch(windFieldRepositoryProvider);
  try {
    return await repo.fetchSeries(hours: windFieldSeriesHours);
  } catch (_) {
    return MockWindFieldRepository().fetchSeries(hours: windFieldSeriesHours);
  }
});
