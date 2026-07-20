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

/// 시간 스크러버가 다룰 시계열 범위: 향후 8일.
/// 격자를 촘촘하게(약 1.4°) 올린 만큼 기간을 2주→8일로 줄여 무료 API
/// 요청량·응답량 균형을 맞춘다(상세 예보 표는 별도 지점 요청으로 16일 유지).
const int windFieldSeriesHours = 24 * 8;

/// 바람장 시계열 결과. [isSynthetic]이 true면 실데이터(Open-Meteo) 호출이
/// 실패해 합성(목업) 바람장으로 폴백한 것 — 지도에 배지로 알려 실데이터와
/// 혼동하지 않게 한다.
class WindSeriesResult {
  const WindSeriesResult({required this.series, required this.isSynthetic});

  final WindFieldSeries series;
  final bool isSynthetic;
}

/// 바람장 시계열 — 지도 화면의 시간 스크러버에 쓰인다.
/// 실패하면 합성 바람장 시계열로 폴백한다. 실데이터(Open-Meteo)를 받아오면
/// [KeepAliveLink]로 세션 동안 캐시해, 탭을 오갈 때마다 무거운 격자 요청을
/// 반복하지 않는다(시간이 지나도 "지금"은 캐시 안에서 찾는다).
/// 목업으로 폴백한 경우엔 캐시하지 않아 다음 진입 때 실데이터를 다시 시도한다.
final windFieldSeriesProvider = FutureProvider.autoDispose<WindSeriesResult>((
  ref,
) async {
  final repo = ref.watch(windFieldRepositoryProvider);
  try {
    final series = await repo.fetchSeries(hours: windFieldSeriesHours);
    ref.keepAlive();
    return WindSeriesResult(series: series, isSynthetic: false);
  } catch (_) {
    return WindSeriesResult(
      series: await MockWindFieldRepository().fetchSeries(
        hours: windFieldSeriesHours,
      ),
      isSynthetic: true,
    );
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
