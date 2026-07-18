import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../../../core/config/env.dart';
import '../../../../core/network/data_go_kr.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/kma_forecast.dart';
import 'kma_weather_repository.dart';

/// 기상청 단기예보((구) 동네예보) 조회서비스 실데이터 리포지토리.
///
/// data.go.kr에 별도 활용신청이 필요하다("기상청_단기예보 ((구)_동네예보)
/// 조회서비스") — 승인되면 기존 [Env.dataGoKrApiKey]를 그대로 쓴다(계정
/// 공통 인증키). https://www.data.go.kr/data/15084084/openapi.do
class DataGoKrKmaRepository implements KmaWeatherRepository {
  DataGoKrKmaRepository({http.Client? client, String? serviceKey})
    : _client = client ?? http.Client(),
      _serviceKey = serviceKey ?? Env.dataGoKrApiKey;

  final http.Client _client;
  final String _serviceKey;

  static const _host = 'apis.data.go.kr';
  static const _path = '/1360000/VilageFcstInfoService_2.0/getVilageFcst';

  /// 단기예보 발표시각(정시+10분 뒤 배포). 매일 8회.
  static const _baseHours = [2, 5, 8, 11, 14, 17, 20, 23];

  /// 가장 최근에 발표됐을 base_date/base_time을 고른다(발표 반영 지연을
  /// 감안해 10분 여유를 둔다).
  (String baseDate, String baseTime) _latestBaseDateTime(DateTime now) {
    final adjusted = now.subtract(const Duration(minutes: 10));
    var date = adjusted;
    var hour = -1;
    for (final h in _baseHours) {
      if (h <= adjusted.hour) hour = h;
    }
    if (hour == -1) {
      date = adjusted.subtract(const Duration(days: 1));
      hour = _baseHours.last;
    }
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return ('$y$m$d', '${hour.toString().padLeft(2, '0')}00');
  }

  @override
  Future<KmaForecast> fetchForecast(SeaLocation location) async {
    final (nx, ny) = _latLonToGrid(location.latitude, location.longitude);
    final (baseDate, baseTime) = _latestBaseDateTime(DateTime.now());

    final uri = Uri.https(_host, _path, {
      'serviceKey': _serviceKey,
      'pageNo': '1',
      'numOfRows': '1000',
      'dataType': 'JSON',
      'base_date': baseDate,
      'base_time': baseTime,
      'nx': nx.toString(),
      'ny': ny.toString(),
    });

    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw http.ClientException('기상청 단기예보 응답 오류 ${res.statusCode}', uri);
    }
    final items = parseDataGoKrItems(res.body);
    if (items.isEmpty) {
      throw const FormatException('기상청 단기예보 응답에 데이터가 없음');
    }
    return KmaForecast(locationId: location.id, hourly: _mapItems(items));
  }

  /// fcstDate+fcstTime별로 category(TMP/SKY/PTY/POP/REH/WSD) 값을 모아
  /// 시간별 레코드로 합친다.
  List<KmaHourly> _mapItems(List<Map<String, dynamic>> items) {
    final byTime = <String, Map<String, String>>{};
    for (final item in items) {
      final date = item['fcstDate']?.toString();
      final time = item['fcstTime']?.toString();
      final category = item['category']?.toString();
      final value = item['fcstValue']?.toString();
      if (date == null || time == null || category == null || value == null) {
        continue;
      }
      byTime.putIfAbsent('$date$time', () => {})[category] = value;
    }

    final keys = byTime.keys.toList()..sort();
    return [
      for (final key in keys)
        if (_toHourly(key, byTime[key]!) case final h?) h,
    ];
  }

  KmaHourly? _toHourly(String key, Map<String, String> v) {
    if (key.length != 12) return null;
    final date = key.substring(0, 8);
    final time = key.substring(8, 12);
    final dt = DateTime(
      int.parse(date.substring(0, 4)),
      int.parse(date.substring(4, 6)),
      int.parse(date.substring(6, 8)),
      int.parse(time.substring(0, 2)),
    );
    return KmaHourly(
      time: dt,
      tempC: double.tryParse(v['TMP'] ?? '') ?? 0,
      skyCode: int.tryParse(v['SKY'] ?? '') ?? 1,
      ptyCode: int.tryParse(v['PTY'] ?? '') ?? 0,
      popPercent: int.tryParse(v['POP'] ?? '') ?? 0,
      humidityPercent: int.tryParse(v['REH'] ?? '') ?? 0,
      windSpeedMs: double.tryParse(v['WSD'] ?? '') ?? 0,
    );
  }

  /// 위경도 → 기상청 격자좌표. Lambert Conformal Conic 투영, 기상청이
  /// 공개한 변환식을 그대로 옮긴 것이다(격자 간격 5km 기준).
  (int nx, int ny) _latLonToGrid(double lat, double lon) {
    const re = 6371.00877;
    const grid = 5.0;
    const slat1 = 30.0, slat2 = 60.0, olon = 126.0, olat = 38.0;
    const xo = 43.0, yo = 136.0;
    const degRad = math.pi / 180.0;

    final re2 = re / grid;
    final sLat1 = slat1 * degRad;
    final sLat2 = slat2 * degRad;
    final oLon = olon * degRad;
    final oLat = olat * degRad;

    final sn =
        math.log(math.cos(sLat1) / math.cos(sLat2)) /
        math.log(
          math.tan(math.pi * 0.25 + sLat2 * 0.5) /
              math.tan(math.pi * 0.25 + sLat1 * 0.5),
        );
    final sf =
        math.pow(math.tan(math.pi * 0.25 + sLat1 * 0.5), sn) *
        math.cos(sLat1) /
        sn;
    final ro = re2 * sf / math.pow(math.tan(math.pi * 0.25 + oLat * 0.5), sn);

    final ra =
        re2 * sf / math.pow(math.tan(math.pi * 0.25 + lat * degRad * 0.5), sn);
    var theta = lon * degRad - oLon;
    if (theta > math.pi) theta -= 2 * math.pi;
    if (theta < -math.pi) theta += 2 * math.pi;
    theta *= sn;

    final x = (ra * math.sin(theta) + xo + 0.5).floor();
    final y = (ro - ra * math.cos(theta) + yo + 0.5).floor();
    return (x, y);
  }
}
