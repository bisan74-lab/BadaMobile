import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/storage/cache_store.dart';
import '../../../../core/utils/kst.dart';
import '../models/wind_field.dart';
import 'wind_field_repository.dart';

/// [inner](실 API)의 바람장 시계열을 로컬에 캐시하는 래퍼 (FR-11 체인).
///
/// - 캐시가 신선하면([freshFor], 기본 3시간) 네트워크 요청 없이 캐시를 쓴다.
///   앱을 열 때마다 무거운 격자 요청(배치 수백 좌표)을 반복하다 무료 API
///   한도에 걸려 지도가 합성 바람으로 떨어지던 일 자체를 줄인다.
/// - 실 요청이 실패하면 오래된 캐시([staleLimit] 이내)로 폴백한다 — 합성
///   목업보다 훨씬 정확하다. 캐시도 없으면 예외를 다시 던져 상위 폴백
///   체인(합성)으로 넘긴다.
/// - u/v는 cm/s 정밀도의 int16으로 양자화해 base64로 저장한다
///   (837점×8일 기준 약 0.9MB — SharedPreferences 허용 범위).
class CachingWindFieldRepository implements WindFieldRepository {
  CachingWindFieldRepository({
    required this.inner,
    required this.cache,
    this.freshFor = const Duration(hours: 3),
    this.staleLimit = const Duration(hours: 48),
  });

  final WindFieldRepository inner;
  final CacheStore cache;

  /// 이 시간 안의 캐시는 네트워크 요청 없이 바로 쓴다(ECMWF 갱신 주기 고려).
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
    await cache.writeJson(_key, {
      'fetchedAt': nowKst().toIso8601String(),
      'start': f0.time.toIso8601String(),
      'hours': n,
      'minLat': f0.minLat,
      'maxLat': f0.maxLat,
      'minLon': f0.minLon,
      'maxLon': f0.maxLon,
      'latSteps': f0.latSteps,
      'lonSteps': f0.lonSteps,
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
      final fetchedAt = DateTime.parse(json['fetchedAt'] as String);
      final start = DateTime.parse(json['start'] as String);
      final n = json['hours'] as int;
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
      final series = WindFieldSeries(
        hourly: [
          for (var h = 0; h < n; h++)
            WindField(
              time: start.add(Duration(hours: h)),
              minLat: minLat,
              maxLat: maxLat,
              minLon: minLon,
              maxLon: maxLon,
              latSteps: latSteps,
              lonSteps: lonSteps,
              u: [for (var k = 0; k < pts; k++) uAll[h * pts + k] / 100.0],
              v: [for (var k = 0; k < pts; k++) vAll[h * pts + k] / 100.0],
            ),
        ],
      );
      return (fetchedAt: fetchedAt, series: series);
    } catch (_) {
      return null; // 손상된 캐시는 없는 것으로 취급
    }
  }
}
