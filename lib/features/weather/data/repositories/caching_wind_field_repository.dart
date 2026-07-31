import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/storage/cache_store.dart';
import '../../../../core/utils/kst.dart';
import '../models/wind_field.dart';
import 'wind_field_repository.dart';

/// [inner](실 API)의 바람장 시계열을 로컬에 캐시하는 래퍼 (FR-11 체인).
///
/// - 캐시가 신선하면([freshFor], 기본 15분) 네트워크 요청 없이 캐시를 쓴다.
///   예전엔 3시간이었는데, 서버가 새 ECMWF 런(태풍 유무가 갈리는 장기 예보
///   갱신)을 올려도 앱이 최대 3시간 동안 옛 캐시만 보여줘 Windy와 어긋났다
///   (사용자 지적: 태풍이 있다가 사라짐). 지금 1순위 소스는 정적 파일 1개
///   다운로드(GitHub CDN)라 자주 확인해도 API 한도와 무관하므로 짧게 줄였다.
///   (Open-Meteo 직접 다지점 호출은 파일 실패 시의 폴백일 때만 나간다.)
/// - 실 요청이 실패하면 오래된 캐시([staleLimit] 이내)로 폴백한다 — 합성
///   목업보다 훨씬 정확하다. 캐시도 없으면 예외를 다시 던져 상위 폴백
///   체인(합성)으로 넘긴다.
/// - u/v는 cm/s 정밀도의 int16으로 양자화해 base64로 저장한다
///   (837점×8일 기준 약 0.9MB — SharedPreferences 허용 범위).
class CachingWindFieldRepository implements WindFieldRepository {
  CachingWindFieldRepository({
    required this.inner,
    required this.cache,
    this.freshFor = const Duration(minutes: 15),
    this.staleLimit = const Duration(hours: 48),
  });

  final WindFieldRepository inner;
  final CacheStore cache;

  /// 이 시간 안의 캐시는 네트워크 요청 없이 바로 쓴다.
  final Duration freshFor;

  /// 실 요청 실패 시 이 시간 안의 캐시까지는 폴백으로 인정한다.
  final Duration staleLimit;

  static const _key = 'wind_series';

  @override
  Future<WindField> fetchField() => inner.fetchField();

  @override
  Future<List<PointWind>> fetchPointSeries(
    double lat,
    double lon, {
    int days = 16,
  }) => inner.fetchPointSeries(lat, lon, days: days);

  @override
  Future<WindFieldSeries> fetchSeries({int hours = 48}) async {
    final cached = _read();
    if (cached != null && _age(cached.fetchedAt) <= freshFor) {
      return cached.series;
    }
    try {
      final series = await inner.fetchSeries(hours: hours);
      await _write(series);
      return series;
    } catch (_) {
      if (cached != null && _age(cached.fetchedAt) <= staleLimit) {
        return cached.series;
      }
      rethrow;
    }
  }

  Duration _age(DateTime fetchedAt) => nowKst().difference(fetchedAt);

  Future<void> _write(WindFieldSeries series) async {
    if (series.hourly.isEmpty) return;
    final f0 = series.hourly.first;
    final n = series.hourly.length;
    final pts = f0.u.length;
    final u = Int16List(n * pts);
    final v = Int16List(n * pts);
    for (var h = 0; h < n; h++) {
      final fu = series.hourly[h].u;
      final fv = series.hourly[h].v;
      for (var k = 0; k < pts; k++) {
        u[h * pts + k] = (fu[k] * 100).clamp(-32000.0, 32000.0).round();
        v[h * pts + k] = (fv[k] * 100).clamp(-32000.0, 32000.0).round();
      }
    }
    // 스텝 간격(시간)도 저장한다 — 서버 파일은 3시간 간격이라, 이걸 안 쓰고
    // 복원 시 1시간 간격으로 가정하면(예전 버그) 15일치 시계열이 5일로
    // 압축돼 지도 스크러버가 실제보다 훨씬 일찍 끝나 보인다.
    final stepHours = n > 1
        ? series.hourly[1].time.difference(f0.time).inHours
        : 1;
    await cache.writeJson(_key, {
      'fetchedAt': nowKst().toIso8601String(),
      'start': f0.time.toIso8601String(),
      'hours': n,
      'stepHours': stepHours <= 0 ? 1 : stepHours,
      // 시간축이 비균일해질 수 있어(앞 구간 1시간·뒤 3시간) 스텝별 실제
      // 경과 시간을 그대로 담는다. stepHours만으로 복원하면 뒷구간 시각이
      // 어긋난다. 없으면(구버전 캐시) stepHours로 균일 복원한다.
      'stepOffsets': [
        for (final h in series.hourly) h.time.difference(f0.time).inHours,
      ],
      'minLat': f0.minLat,
      'maxLat': f0.maxLat,
      'minLon': f0.minLon,
      'maxLon': f0.maxLon,
      'latSteps': f0.latSteps,
      'lonSteps': f0.lonSteps,
      // 적응형(비균일) 격자의 실제 축 좌표 — 왕복하지 않으면 복원 시 균일
      // 격자로 잘못 재구성돼 캐시에서 읽은 필드만 보간이 다시 뭉개진다.
      'lats': f0.lats,
      'lons': f0.lons,
      // 스텝별 데이터 유무(회색 처리용). 캐시 왕복에도 보존해야 재요청 전엔
      // 계속 정확하다.
      'valid': [for (final h in series.hourly) h.hasData ? 1 : 0],
      'u': base64Encode(u.buffer.asUint8List()),
      'v': base64Encode(v.buffer.asUint8List()),
    });
  }

  ({DateTime fetchedAt, WindFieldSeries series})? _read() {
    final json = cache.readJson(_key);
    if (json == null) return null;
    try {
      // 격자 구성은 데이터마다 다를 수 있다(서버 파일 vs 직접 호출). 크기를
      // 강제하지 않고, 배열 길이가 스텝×격자와 맞는지로만 무결성을 검증한다.
      // stepHours가 없는 캐시는 이 필드를 추가하기 전(버그 있던 버전)에 쓰인
      // 것이다. 1로 기본값을 주면 3시간 간격 데이터를 1시간 간격으로 잘못
      // 복원하는 예전 버그가 새 코드에서도 재현된다(수정한 빌드를 설치해도
      // 기존 캐시가 3시간 안(freshFor)엔 계속 쓰여 바로 고쳐지지 않음).
      // 그래서 이런 캐시는 아예 "없는 것"으로 취급해 즉시 재요청하게 한다.
      if (json['stepHours'] == null) return null;
      final fetchedAt = DateTime.parse(json['fetchedAt'] as String);
      final start = DateTime.parse(json['start'] as String);
      final n = json['hours'] as int;
      final stepHours = json['stepHours'] as int;
      final latSteps = json['latSteps'] as int;
      final lonSteps = json['lonSteps'] as int;
      final minLat = (json['minLat'] as num).toDouble();
      final maxLat = (json['maxLat'] as num).toDouble();
      final minLon = (json['minLon'] as num).toDouble();
      final maxLon = (json['maxLon'] as num).toDouble();
      final uBytes = base64Decode(json['u'] as String);
      final vBytes = base64Decode(json['v'] as String);
      final uAll = uBytes.buffer.asInt16List(
        uBytes.offsetInBytes,
        uBytes.length ~/ 2,
      );
      final vAll = vBytes.buffer.asInt16List(
        vBytes.offsetInBytes,
        vBytes.length ~/ 2,
      );
      final pts = latSteps * lonSteps;
      if (uAll.length != n * pts || vAll.length != n * pts) return null;
      // 적응형 격자 축 좌표 — 없으면(구버전 캐시) WindField가 균일 격자로
      // 재구성한다.
      final latsRaw = json['lats'] as List?;
      final lonsRaw = json['lons'] as List?;
      final lats = latsRaw?.map((e) => (e as num).toDouble()).toList();
      final lons = lonsRaw?.map((e) => (e as num).toDouble()).toList();
      // 예전 캐시(필드 없음)는 전부 유효한 것으로 취급한다(당시엔 결측
      // 스텝을 아예 잘라내고 저장했으므로 안전한 기본값).
      final validRaw = json['valid'] as List?;
      // 비균일 시간축(fmt 3+). 없으면 stepHours로 균일 복원(구버전 캐시).
      final offsetsRaw = json['stepOffsets'] as List?;
      final series = WindFieldSeries(
        hourly: [
          for (var h = 0; h < n; h++)
            WindField(
              time: start.add(
                Duration(
                  hours: offsetsRaw != null && h < offsetsRaw.length
                      ? (offsetsRaw[h] as num).toInt()
                      : h * stepHours,
                ),
              ),
              minLat: minLat,
              maxLat: maxLat,
              minLon: minLon,
              maxLon: maxLon,
              latSteps: latSteps,
              lonSteps: lonSteps,
              lats: lats,
              lons: lons,
              u: [for (var k = 0; k < pts; k++) uAll[h * pts + k] / 100.0],
              v: [for (var k = 0; k < pts; k++) vAll[h * pts + k] / 100.0],
              hasData:
                  validRaw == null ||
                  (h < validRaw.length && (validRaw[h] as num) != 0),
            ),
        ],
      );
      return (fetchedAt: fetchedAt, series: series);
    } catch (_) {
      return null; // 손상된 캐시는 없는 것으로 취급
    }
  }
}
