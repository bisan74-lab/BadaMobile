import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

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
  static const double minLat = 21.0, maxLat = 54.0;
  static const double minLon = 112.0, maxLon = 144.0;

  /// 격자 해상도. 넓어진 범위를 적당한 밀도로 덮되(한 번의 다지점 요청 크기를
  /// 고려) 파티클은 이 격자를 쌍선형 보간해 흐른다.
  static const int latSteps = 18, lonSteps = 20;

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

  @override
  Future<WindField> fetchField() async {
    final lats = _latGrid();
    final lons = _lonGrid();

    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lats.map((v) => v.toStringAsFixed(3)).join(','),
      'longitude': lons.map((v) => v.toStringAsFixed(3)).join(','),
      'current': 'wind_speed_10m,wind_direction_10m',
      'wind_speed_unit': 'ms',
      'timezone': 'Asia/Seoul',
      'models': _model,
    });

    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw http.ClientException('바람장 응답 오류 ${res.statusCode}', uri);
    }
    final decoded = jsonDecode(res.body);
    final list = decoded is List ? decoded : [decoded];
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
      time: time ?? DateTime.now(),
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

    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lats.map((v) => v.toStringAsFixed(3)).join(','),
      'longitude': lons.map((v) => v.toStringAsFixed(3)).join(','),
      'hourly': 'wind_speed_10m,wind_direction_10m',
      'wind_speed_unit': 'ms',
      'timezone': 'Asia/Seoul',
      'forecast_days': forecastDays.toString(),
      'models': _model,
    });

    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw http.ClientException('바람장 시계열 응답 오류 ${res.statusCode}', uri);
    }
    final decoded = jsonDecode(res.body);
    final list = decoded is List ? decoded : [decoded];
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
}
