import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../../../core/utils/kst.dart';
import '../models/wind_field.dart';
import 'wind_field_repository.dart';

/// 한반도 주변 해역 바람장(격자) 리포지토리.
///
/// Open-Meteo Forecast API의 다중 좌표 요청(콤마 구분 latitude/longitude)으로
/// 격자점마다 바람을 받아온다. [fetchField]는 `current` 파라미터로 지금
/// 시점만 가볍게, [fetchSeries]는 `hourly` 파라미터로 여러 시간대를 한 번에
/// 받아 시간 스크러버(time slider)에 쓴다.
/// https://open-meteo.com/en/docs
class OpenMeteoWindFieldRepository implements WindFieldRepository {
  OpenMeteoWindFieldRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  // 지도 기본 화면뷰(features/weather/presentation/widgets/map_projection.dart의
  // mapViewBounds)와 같은 범위 — 대한민국이 중심에 오고 중국 동해안·일본까지
  // 포함한 지도 전체에 바람 히트맵이 채워지도록 격자를 그만큼 넓게 잡는다.
  // Open-Meteo는 위경도만 주면 전 세계 어디든 응답하므로(별도 글로벌 API
  // 연동 불필요) 범위만 넓히면 된다.
  // 지도 뷰(mapViewBounds)와 같은 넓은 범위 — 한국 주변 동아시아 해역 전체.
  // 동서남북 끝을 조금씩 더 넓혀(위도 18~57, 경도 108~148) 지도를 확대·이동해도
  // 가장자리에 빈(검은) 부분이 덜 보이게 한다.
  static const double minLat = 18.0, maxLat = 57.0;
  static const double minLon = 108.0, maxLon = 148.0;

  /// 격자 해상도. **총 좌표 수는 반드시 600 미만**이어야 한다 — Open-Meteo
  /// 무료 한도가 분당 600콜이고 다지점 요청은 좌표 1개=1콜로 계산돼, 이를
  /// 넘기면(한때 837점으로 올렸다가) 요청 한 번에 분당 한도를 초과해 매번
  /// 429로 거부되고 지도가 항상 합성 폴백으로 떨어진다. 504점(약 2° 간격)은
  /// 실사용으로 검증된 값이다. 색 세밀함은 래스터 보간이 채우고, 탭 지점
  /// 숫자는 별도 원해상도 지점 요청으로 맞춘다.
  static const int latSteps = 21, lonSteps = 24;

  /// 바람 데이터 출처 모델. Windy 기본 레이어와 같은 ECMWF(IFS 0.25°)를 써서
  /// 바람 방향·세기를 Windy와 최대한 일치시킨다. 응답이 없으면(모델 미제공 등)
  /// 상위 조립부의 캐싱→목업 폴백 체인이 앱 실행을 막지 않는다.
  static const String _model = 'ecmwf_ifs025';

  List<double> _latGrid() {
    final step = (maxLat - minLat) / (latSteps - 1);
    return [
      for (var i = 0; i < latSteps; i++)
        for (var j = 0; j < lonSteps; j++) minLat + i * step,
    ];
  }

  List<double> _lonGrid() {
    final step = (maxLon - minLon) / (lonSteps - 1);
    return [
      for (var i = 0; i < latSteps; i++)
        for (var j = 0; j < lonSteps; j++) minLon + j * step,
    ];
  }

  /// 한 요청에 담는 최대 좌표 수. Open-Meteo 다중 좌표 요청은 URL 길이·좌표
  /// 개수 제한이 있어, 전체 격자(수백 점)를 한 번에 보내면 URL이 수천 자가
  /// 되어 서버가 거부한다(414 등 → 조용히 목업으로 폴백해 화면이 균일한
  /// 합성 바람으로 채워졌다). 좌표를 이만큼씩 잘라 여러 번(병렬) 요청하고
  /// 격자 순서대로 합쳐, 실제 ECMWF 바람이 지도에 뜨게 한다.
  static const int _batchSize = 100;

  /// 일시 오류(레이트리밋 429·서버 5xx·순간 네트워크 끊김)에 대비해 한 번
  /// 재시도한다. 배치 하나만 실패해도 시계열 전체가 목업으로 폴백돼 지도가
  /// 합성 바람으로 바뀌므로, 재시도가 실데이터 표시율을 크게 올린다.
  Future<http.Response> _getWithRetry(Uri uri) async {
    try {
      final res = await _client.get(uri);
      if (res.statusCode == 200) return res;
    } catch (_) {
      // 아래에서 한 번 더 시도한다.
    }
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    return _client.get(uri);
  }

  /// [lats]/[lons] 좌표들을 [_batchSize]개씩 잘라 병렬 요청하고, 좌표(격자)
  /// 순서를 유지한 채 각 지점의 결과(JSON 객체)를 이어 붙여 돌려준다.
  /// [extraParams]에는 요청별로 다른 부분(current 또는 hourly·forecast_days)만
  /// 넣고, 공통 파라미터(단위·시간대·모델)는 여기서 붙인다.
  Future<List<dynamic>> _fetchLocations(
    Map<String, String> extraParams,
    List<double> lats,
    List<double> lons,
  ) async {
    final ranges = <(int, int)>[];
    for (var start = 0; start < lats.length; start += _batchSize) {
      ranges.add((start, math.min(start + _batchSize, lats.length)));
    }
    final batches = await Future.wait(
      ranges.map((r) async {
        final (start, end) = r;
        final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
          'latitude': lats
              .sublist(start, end)
              .map((v) => v.toStringAsFixed(2))
              .join(','),
          'longitude': lons
              .sublist(start, end)
              .map((v) => v.toStringAsFixed(2))
              .join(','),
          'wind_speed_unit': 'ms',
          'timezone': 'Asia/Seoul',
          'models': _model,
          ...extraParams,
        });
        final res = await _getWithRetry(uri);
        if (res.statusCode != 200) {
          throw http.ClientException('바람장 응답 오류 ${res.statusCode}', uri);
        }
        final decoded = jsonDecode(res.body);
        return decoded is List ? decoded : [decoded];
      }),
    );
    return [for (final b in batches) ...b];
  }

  @override
  Future<WindField> fetchField() async {
    final lats = _latGrid();
    final lons = _lonGrid();

    final list = await _fetchLocations(
      {'current': 'wind_speed_10m,wind_direction_10m'},
      lats,
      lons,
    );
    if (list.length != lats.length) {
      throw FormatException(
        '바람장 응답 개수 불일치: 기대 ${lats.length}, 실제 ${list.length}',
      );
    }

    final uArr = List<double>.filled(lats.length, 0);
    final vArr = List<double>.filled(lats.length, 0);
    DateTime? time;
    for (var k = 0; k < list.length; k++) {
      final current =
          (list[k] as Map<String, dynamic>)['current'] as Map<String, dynamic>?;
      if (current == null) continue;
      final speed = (current['wind_speed_10m'] as num?)?.toDouble() ?? 0;
      final dir = (current['wind_direction_10m'] as num?)?.toDouble() ?? 0;
      final (u, v) = windToUv(speed, dir);
      uArr[k] = u;
      vArr[k] = v;
      time ??= DateTime.tryParse(current['time']?.toString() ?? '');
    }

    return WindField(
      time: time ?? nowKst(),
      minLat: minLat,
      maxLat: maxLat,
      minLon: minLon,
      maxLon: maxLon,
      latSteps: latSteps,
      lonSteps: lonSteps,
      u: uArr,
      v: vArr,
    );
  }

  @override
  Future<WindFieldSeries> fetchSeries({int hours = 48}) async {
    final lats = _latGrid();
    final lons = _lonGrid();
    final forecastDays = ((hours / 24).ceil() + 1).clamp(1, 16);

    final list = await _fetchLocations(
      {
        'hourly': 'wind_speed_10m,wind_direction_10m',
        'forecast_days': forecastDays.toString(),
      },
      lats,
      lons,
    );
    if (list.length != lats.length) {
      throw FormatException(
        '바람장 시계열 응답 개수 불일치: 기대 ${lats.length}, 실제 ${list.length}',
      );
    }

    // 모든 지점이 같은 timezone·forecast_days로 요청됐으므로 시간축은
    // 첫 지점 기준으로 통일해 쓴다.
    final firstHourly =
        (list[0] as Map<String, dynamic>)['hourly'] as Map<String, dynamic>?;
    final times = ((firstHourly?['time'] as List?) ?? const [])
        .map((v) => DateTime.parse(v as String))
        .toList();
    final steps = math.min(hours, times.length);
    if (steps == 0) {
      throw const FormatException('바람장 시계열 응답에 시간별 데이터가 없음');
    }

    final uByHour = List.generate(
      steps,
      (_) => List<double>.filled(lats.length, 0),
    );
    final vByHour = List.generate(
      steps,
      (_) => List<double>.filled(lats.length, 0),
    );

    for (var k = 0; k < list.length; k++) {
      final hourly =
          (list[k] as Map<String, dynamic>)['hourly'] as Map<String, dynamic>?;
      if (hourly == null) continue;
      final speeds = (hourly['wind_speed_10m'] as List?) ?? const [];
      final dirs = (hourly['wind_direction_10m'] as List?) ?? const [];
      for (var h = 0; h < steps; h++) {
        final speed =
            (h < speeds.length ? speeds[h] as num? : null)?.toDouble() ?? 0;
        final dir = (h < dirs.length ? dirs[h] as num? : null)?.toDouble() ?? 0;
        final (u, v) = windToUv(speed, dir);
        uByHour[h][k] = u;
        vByHour[h][k] = v;
      }
    }

    return WindFieldSeries(
      hourly: List.generate(
        steps,
        (h) => WindField(
          time: times[h],
          minLat: minLat,
          maxLat: maxLat,
          minLon: minLon,
          maxLon: maxLon,
          latSteps: latSteps,
          lonSteps: lonSteps,
          u: uByHour[h],
          v: vByHour[h],
        ),
      ),
    );
  }

  @override
  Future<List<PointWind>> fetchPointSeries(
    double lat,
    double lon, {
    int days = 16,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lon.toStringAsFixed(4),
      'hourly': 'wind_speed_10m,wind_direction_10m',
      'wind_speed_unit': 'ms',
      'timezone': 'Asia/Seoul',
      'forecast_days': days.clamp(1, 16).toString(),
      'models': _model,
    });
    final res = await _getWithRetry(uri);
    if (res.statusCode != 200) {
      throw http.ClientException('지점 바람 응답 오류 ${res.statusCode}', uri);
    }
    final decoded = jsonDecode(res.body);
    final obj =
        (decoded is List ? decoded.first : decoded) as Map<String, dynamic>;
    final hourly = obj['hourly'] as Map<String, dynamic>?;
    final times = (hourly?['time'] as List?) ?? const [];
    final speeds = (hourly?['wind_speed_10m'] as List?) ?? const [];
    final dirs = (hourly?['wind_direction_10m'] as List?) ?? const [];
    if (times.isEmpty) {
      throw const FormatException('지점 바람 응답에 시간별 데이터가 없음');
    }
    return [
      for (var i = 0; i < times.length; i++)
        PointWind(
          time: DateTime.parse(times[i] as String),
          speedMs:
              (i < speeds.length ? speeds[i] as num? : null)?.toDouble() ?? 0,
          directionDeg:
              (i < dirs.length ? dirs[i] as num? : null)?.toDouble() ?? 0,
        ),
    ];
  }
}
