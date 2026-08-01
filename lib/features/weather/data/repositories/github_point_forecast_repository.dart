import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/env.dart';
import '../../../../core/storage/cache_store.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/marine_weather.dart';
import 'marine_weather_repository.dart';

/// 서버(GitHub Actions 크론)가 3시간마다 모아 롤링 릴리스에 올린 지역별 예보를
/// 내려받아 쓰는 리포지토리. 바람장·낚시지수와 같은 구조다.
///
/// **왜 이렇게 하나** — [OpenMeteoMarineRepository]는 지역 하나당 요청이 5번
/// 나가서(WAM 총파고·WAM 너울·GFS·수온·육상예보) 새 지역마다 1~2초가 걸린다.
/// 홈 화면과 낚시정보 카드가 쓰는 건 날짜별 대표값 하나씩뿐이라, 서버가 3시간
/// 간격으로 모아 두면 앱은 파일 하나(약 100KB)로 끝나고 지역 변경은 네트워크
/// 없이 처리된다. 3시간 간격이면 대표값 선택 오차가 최대 1.5시간이다.
///
/// **상세 예보 화면은 이 파일을 쓰지 않는다** — 너울·파력 등 이 파일에 없는
/// 값이 필요하고 정밀도도 중요해서 [direct]를 그대로 쓴다.
///
/// 파일에 없는 지역(사용자가 검색으로 추가한 좌표 등)이나 다운로드 실패는
/// [direct]로 폴백한다.
class GithubPointForecastRepository implements MarineWeatherRepository {
  GithubPointForecastRepository({
    required this.direct,
    required this.cache,
    http.Client? client,
    String? url,
  }) : _client = client ?? http.Client(),
       _url = url ?? Env.pointForecastUrl;

  final MarineWeatherRepository direct;
  final CacheStore cache;
  final http.Client _client;
  final String _url;

  static const _timeout = Duration(seconds: 12);
  static const _cacheKey = 'point_forecast';

  /// 파일을 다시 받아 볼 간격. 서버가 3시간마다 갱신하므로 그보다 짧게 잡아
  /// 두면 새 예보가 나오는 대로 반영된다. 재시도가 실패해도 이전 파일을
  /// 계속 쓰므로(오프라인 등) 화면이 비지 않는다.
  static const _refreshAfter = Duration(hours: 1);

  static Future<PointForecastFile>? _memo;
  static DateTime? _memoAt;

  @visibleForTesting
  static void clearMemoryCache() {
    _memo = null;
    _memoAt = null;
  }

  @override
  Future<MarineForecast> fetchForecast(
    SeaLocation location, {
    int hours = defaultForecastHours,
    int pastDays = 0,
  }) async {
    if (_url.isEmpty) {
      return direct.fetchForecast(location, hours: hours, pastDays: pastDays);
    }
    try {
      final file = await _cached();
      final forecast = file.forecastFor(location, pastDays: pastDays);
      if (forecast == null) throw StateError('파일에 없는 지역: ${location.id}');
      return forecast;
    } catch (_) {
      return direct.fetchForecast(location, hours: hours, pastDays: pastDays);
    }
  }

  Future<PointForecastFile> _cached() {
    final at = _memoAt;
    final memo = _memo;
    if (memo != null &&
        at != null &&
        DateTime.now().difference(at) < _refreshAfter) {
      return memo;
    }
    final next = _load();
    _memo = next;
    _memoAt = DateTime.now();
    // 실패하면 다음 조회에서 다시 시도하도록 메모를 비운다. 오류는 호출자가
    // 받은 [next]에서 처리하므로 여기서는 삼킨다(다시 던지면 아무도 받지
    // 않는 두 번째 Future가 생겨 "unhandled error"가 된다).
    unawaited(next.then((_) {}, onError: (_) => clearMemoryCache()));
    return next;
  }

  Future<PointForecastFile> _load() async {
    try {
      final res = await _client.get(Uri.parse(_url)).timeout(_timeout);
      if (res.statusCode != 200) {
        throw http.ClientException('지점 예보 파일 응답 오류 ${res.statusCode}');
      }
      var bytes = res.bodyBytes;
      if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        bytes = Uint8List.fromList(gzip.decode(bytes));
      }
      final json = utf8.decode(bytes);
      final file = await compute(parsePointForecastFile, json);
      unawaited(cache.writeString(_cacheKey, json).catchError((_) {}));
      return file;
    } catch (_) {
      // 오프라인이면 마지막으로 받아 둔 파일을 쓴다. 3시간 간격 데이터라
      // 조금 묵어도 화면이 비는 것보다 낫다.
      final cached = cache.readString(_cacheKey);
      if (cached != null) return compute(parsePointForecastFile, cached);
      rethrow;
    }
  }
}

/// [fetch_points.py]가 만든 파일. 지역 → 변수 → 시각 순의 2차원 배열이다.
@immutable
class PointForecastFile {
  const PointForecastFile({
    required this.times,
    required this.byLocation,
    required this.generated,
  });

  final List<DateTime> times;

  /// 지역 id → 시각별 값.
  final Map<String, List<HourlyMarine>> byLocation;

  final DateTime? generated;

  /// [location]의 예보. 파일에 없는 지역이면 null(호출자가 직접 호출로 폴백).
  ///
  /// [pastDays]가 0이면 과거 구간을 잘라 낸다 — 파일은 홈 화면의 날짜 이동을
  /// 위해 과거 2주를 담고 있지만, 과거가 필요 없는 호출자는 첫 항목이
  /// "지금"이기를 기대한다([MarineForecast.current]).
  MarineForecast? forecastFor(SeaLocation location, {int pastDays = 0}) {
    final all = byLocation[location.id];
    if (all == null || all.isEmpty) return null;

    final from = pastDays > 0
        ? DateTime.now().subtract(Duration(days: pastDays))
        : DateTime.now().subtract(const Duration(hours: 3));
    final hourly = [
      for (final h in all)
        if (!h.time.isBefore(from)) h,
    ];
    if (hourly.isEmpty) return null;

    return MarineForecast(
      locationId: location.id,
      hourly: hourly,
      hasWaveData: hourly.any((h) => h.waveHeightM > 0),
    );
  }
}

/// 파일 JSON 문자열을 [PointForecastFile]로 파싱한다.
/// [compute]로 넘기려고 최상위 함수로 둔다.
PointForecastFile parsePointForecastFile(String source) {
  final json = jsonDecode(source) as Map<String, dynamic>;

  final vars = [
    for (final v in (json['vars'] as List? ?? const [])) v.toString(),
  ];
  final times = [
    for (final t in (json['times'] as List? ?? const []))
      DateTime.parse(t.toString()),
  ];
  final ids = [
    for (final l in (json['locations'] as List? ?? const [])) l.toString(),
  ];
  final series = json['series'] as List? ?? const [];

  int col(String name) => vars.indexOf(name);
  final iWind = col('windMs');
  final iGust = col('gustMs');
  final iDir = col('dirDeg');
  final iWave = col('waveM');
  final iPeriod = col('periodS');
  final iSst = col('sstC');
  final iAir = col('airC');

  final byLocation = <String, List<HourlyMarine>>{};
  for (var n = 0; n < ids.length && n < series.length; n++) {
    final cols = series[n] as List;
    double at(int c, int t) {
      if (c < 0 || c >= cols.length) return 0;
      final list = cols[c] as List;
      if (t >= list.length) return 0;
      return (list[t] as num?)?.toDouble() ?? 0;
    }

    byLocation[ids[n]] = [
      for (var t = 0; t < times.length; t++)
        HourlyMarine(
          time: times[t],
          windSpeedMs: at(iWind, t),
          windGustMs: at(iGust, t),
          windDirectionDeg: at(iDir, t),
          waveHeightM: at(iWave, t),
          wavePeriodS: at(iPeriod, t),
          waveDirectionDeg: 0, // 이 파일엔 없다(쓰는 화면도 없다).
          waterTempC: at(iSst, t),
          airTempC: at(iAir, t),
        ),
    ];
  }

  return PointForecastFile(
    times: times,
    byLocation: byLocation,
    generated: DateTime.tryParse(json['generated']?.toString() ?? ''),
  );
}
