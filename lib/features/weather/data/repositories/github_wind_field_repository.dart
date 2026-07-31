import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../../core/config/env.dart';
import '../models/wind_field.dart';
import 'wind_field_repository.dart';

/// 서버(GitHub Actions 크론)가 미리 뽑아 롤링 릴리스에 올린 바람장 격자
/// 파일을 내려받아 시계열을 만드는 리포지토리.
///
/// 앱이 Open-Meteo를 직접 다지점 호출하지 않으므로 사용자 수·분당 호출
/// 한도와 무관하게 항상 같은 실데이터를 쓴다(색 디테일도 서버에서 더 촘촘한
/// 격자로 뽑을 수 있다). 파일을 못 받으면 [direct](Open-Meteo 직접 호출)로
/// 폴백한다. 현재 시점 스냅샷([fetchField])·탭 지점 값([fetchPointSeries])은
/// 정확·경량이라 항상 [direct]를 쓴다.
class GithubWindFieldRepository implements WindFieldRepository {
  GithubWindFieldRepository({
    required this.direct,
    http.Client? client,
    String? url,
  }) : _client = client ?? http.Client(),
       _url = url ?? Env.windDataUrl;

  final WindFieldRepository direct;
  final http.Client _client;
  final String _url;

  static const _timeout = Duration(seconds: 20);

  @override
  Future<WindField> fetchField() => direct.fetchField();

  @override
  Future<List<PointWind>> fetchPointSeries(
    double lat,
    double lon, {
    int days = 16,
  }) => direct.fetchPointSeries(lat, lon, days: days);

  @override
  Future<WindFieldSeries> fetchSeries({int hours = 48}) async {
    if (_url.isEmpty) return direct.fetchSeries(hours: hours);
    try {
      return await _fetchFromServer();
    } catch (_) {
      // 서버 파일을 못 받으면 앱이 직접 Open-Meteo에서 받아 온다.
      return direct.fetchSeries(hours: hours);
    }
  }

  Future<WindFieldSeries> _fetchFromServer() async {
    final res = await _client.get(Uri.parse(_url)).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('바람장 파일 응답 오류 ${res.statusCode}');
    }
    var bytes = res.bodyBytes;
    // gzip 매직(0x1f 0x8b)이면 직접 해제한다(릴리스 첨부는 raw .gz로 온다).
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      bytes = Uint8List.fromList(gzip.decode(bytes));
    }
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return parseWindFieldFile(json);
  }
}

/// [fetch_wind.py]가 만든 파일 JSON을 [WindFieldSeries]로 파싱한다.
/// u/v는 cm/s 정밀도 int16(리틀엔디안) 배열을 base64로 담고, 순서는
/// [step][위도 오름차순 i × 경도 오름차순 j], index = i*lonSteps + j.
WindFieldSeries parseWindFieldFile(Map<String, dynamic> json) {
  final minLat = (json['minLat'] as num).toDouble();
  final maxLat = (json['maxLat'] as num).toDouble();
  final minLon = (json['minLon'] as num).toDouble();
  final maxLon = (json['maxLon'] as num).toDouble();
  final latSteps = json['latSteps'] as int;
  final lonSteps = json['lonSteps'] as int;
  final steps = json['steps'] as int;
  final stepHours = (json['stepHours'] as num?)?.toInt() ?? 1;
  final start = DateTime.parse(json['start'] as String);
  final pts = latSteps * lonSteps;

  // fmt 2+: 적응형(비균일) 격자의 실제 축 좌표. 없으면(구버전 fmt 1 파일)
  // WindField가 minLat/maxLat/latSteps로 균일 격자를 재구성한다.
  final latsRaw = json['lats'] as List?;
  final lonsRaw = json['lons'] as List?;
  final lats = latsRaw?.map((e) => (e as num).toDouble()).toList();
  final lons = lonsRaw?.map((e) => (e as num).toDouble()).toList();

  // fmt 3+: 시간축도 비균일이다(앞 48시간은 1시간, 그 뒤는 3시간 간격).
  // stepOffsets는 start로부터의 경과 시간(시간 단위)이라 그대로 더하면 된다.
  // 없으면(구버전 파일·캐시) stepHours로 균일 간격을 가정해 재구성한다.
  final offsetsRaw = json['stepOffsets'] as List?;
  DateTime timeAt(int s) => start.add(
    Duration(
      hours: offsetsRaw != null && s < offsetsRaw.length
          ? (offsetsRaw[s] as num).toInt()
          : s * stepHours,
    ),
  );

  final uBytes = base64Decode(json['u'] as String);
  final vBytes = base64Decode(json['v'] as String);
  final u = uBytes.buffer.asInt16List(uBytes.offsetInBytes, uBytes.length ~/ 2);
  final v = vBytes.buffer.asInt16List(vBytes.offsetInBytes, vBytes.length ~/ 2);
  if (u.length < steps * pts || v.length < steps * pts) {
    throw const FormatException('바람장 파일 배열 길이가 격자·스텝과 맞지 않음');
  }

  // 모델 예보 한계를 넘어 0으로 채워진 스텝(=결측)은 **자르지 않고** 그대로
  // 남겨(최신·최장 데이터 우선) hasData만 false로 표시한다 — 지도가 이
  // 스텝을 회색(데이터 없음)으로 그릴 수 있게. valid 배열이 없는 예전 파일은
  // 격자 전부가 정확히 0인 스텝을 결측으로 간주하는 이전 방식으로 대체한다
  // (실제 바람장은 수천 격자 중 하나라도 0이 아니므로 이 휴리스틱이 안전하다).
  final validRaw = json['valid'] as List?;
  bool hasDataFor(int s) {
    if (validRaw != null) {
      return s < validRaw.length && (validRaw[s] as num) != 0;
    }
    final base = s * pts;
    for (var k = 0; k < pts; k++) {
      if (u[base + k] != 0 || v[base + k] != 0) return true;
    }
    return false;
  }

  return WindFieldSeries(
    hourly: [
      for (var s = 0; s < steps; s++)
        WindField(
          time: timeAt(s),
          minLat: minLat,
          maxLat: maxLat,
          minLon: minLon,
          maxLon: maxLon,
          latSteps: latSteps,
          lonSteps: lonSteps,
          lats: lats,
          lons: lons,
          u: [for (var k = 0; k < pts; k++) u[s * pts + k] / 100.0],
          v: [for (var k = 0; k < pts; k++) v[s * pts + k] / 100.0],
          hasData: hasDataFor(s),
        ),
    ],
  );
}
