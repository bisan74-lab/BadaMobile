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
/// 실패하면 합성 바람장 시계열로 폴백한다. 실데이터(Open-Meteo)를 받아오면
/// [KeepAliveLink]로 세션 동안 캐시해, 탭을 오갈 때마다 무거운 격자 요청을
/// 반복하지 않는다(2주 시계열이라 시간이 지나도 "지금"은 캐시 안에서 찾는다).
/// 목업으로 폴백한 경우엔 캐시하지 않아 다음 진입 때 실데이터를 다시 시도한다.
final windFieldSeriesProvider = FutureProvider.autoDispose<WindFieldSeries>((
  ref,
) async {
  final repo = ref.watch(windFieldRepositoryProvider);
  try {
    final series = await repo.fetchSeries(hours: windFieldSeriesHours);
    ref.keepAlive();
    return series;
  } catch (_) {
    return MockWindFieldRepository().fetchSeries(hours: windFieldSeriesHours);
  }
});

/// 커서(탭한 지점)의 시간별 바람. 지도 격자(약 2° 간격) 보간은 국지 바람이
/// 뭉개져 실제보다 약하게 나오므로(윈디 지점 표시는 원해상도 지점값),
/// 상단 커서 바의 숫자는 좌표를 그대로 요청한 이 지점값을 쓴다.
/// 실패하면 화면이 격자 보간값으로 폴백한다(별도 목업 폴백 없음).
final cursorWindSeriesProvider = FutureProvider.autoDispose
    .family<List<PointWind>, ({double lat, double lon})>((ref, p) async {
      final repo = ref.watch(windFieldRepositoryProvider);
      final list = await repo.fetchPointSeries(p.lat, p.lon);
      ref.keepAlive();
      return list;
    });
