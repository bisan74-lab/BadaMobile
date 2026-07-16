import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/wind_field.dart';
import 'wind_field_repository.dart';

/// 한반도 주변 해역 바람장(격자) 리포지토리.
///
/// Open-Meteo Forecast API의 다중 좌표 요청(콤마 구분 latitude/longitude)과
/// `current` 파라미터로 격자점마다 "지금" 풍속·풍향만 가볍게 받아온다.
/// https://open-meteo.com/en/docs
class OpenMeteoWindFieldRepository implements WindFieldRepository {
  OpenMeteoWindFieldRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const double minLat = 33.0, maxLat = 38.7;
  static const double minLon = 124.3, maxLon = 131.0;
  static const int latSteps = 8, lonSteps = 10;

  @override
  Future<WindField> fetchField() async {
    final lats = <double>[];
    final lons = <double>[];
    final latStep = (maxLat - minLat) / (latSteps - 1);
    final lonStep = (maxLon - minLon) / (lonSteps - 1);
    for (var i = 0; i < latSteps; i++) {
      final lat = minLat + i * latStep;
      for (var j = 0; j < lonSteps; j++) {
        lats.add(lat);
        lons.add(minLon + j * lonStep);
      }
    }

    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lats.map((v) => v.toStringAsFixed(3)).join(','),
      'longitude': lons.map((v) => v.toStringAsFixed(3)).join(','),
      'current': 'wind_speed_10m,wind_direction_10m',
      'wind_speed_unit': 'ms',
      'timezone': 'Asia/Seoul',
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
}
