import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/cache_store.dart';
import '../data/models/wind_field.dart';
import '../data/repositories/caching_wind_field_repository.dart';
import '../data/repositories/github_wind_field_repository.dart';
import '../data/repositories/mock_wind_field_repository.dart';
import '../data/repositories/open_meteo_wind_field_repository.dart';
import '../data/repositories/wind_field_repository.dart';

/// 바람장 리포지토리 주입 지점 — 서버 파일 → Open-Meteo 직접 → 캐싱 →
/// (provider의) 합성 폴백 체인.
///
/// 1순위는 서버(GitHub Actions 크론)가 미리 뽑아 릴리스에 올린 정적 파일이다
/// (사용자 기기가 Open-Meteo를 직접 호출하지 않아 분당 한도와 무관하고, 더
/// 촘촘한 격자로 색 디테일↑). 파일을 못 받으면 Open-Meteo 직접 호출로,
/// 그마저 실패하면 캐시로, 캐시도 없으면 합성으로 내려간다.
final windFieldRepositoryProvider = Provider<WindFieldRepository>(
  (ref) => CachingWindFieldRepository(
    inner: GithubWindFieldRepository(direct: OpenMeteoWindFieldRepository()),
    cache: ref.watch(cacheStoreProvider),
  ),
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

/// 시간 스크러버가 다룰 시계열 범위: 향후 16일(모델 상한). 지도 1순위는
/// 서버 파일이라 앱 직접호출은 폴백일 때만 이 범위로 요청한다.
const int windFieldSeriesHours = 24 * 16;

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
    // 분당 호출 한도 등 일시 제한일 수 있으니, 한도 창(1분)이 지난 뒤 자동으로
    // 다시 시도한다. 화면이 열려 있는 동안 실데이터가 도착하면 합성 배지가
    // 사라지고 지도가 실바람으로 바뀐다.
    final timer = Timer(const Duration(seconds: 75), ref.invalidateSelf);
    ref.onDispose(timer.cancel);
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
