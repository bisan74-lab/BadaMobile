import 'dart:convert';
import 'dart:typed_data';

import 'package:bada_mobile/features/weather/data/models/wind_field.dart';
import 'package:bada_mobile/features/weather/data/repositories/github_wind_field_repository.dart';
import 'package:bada_mobile/features/weather/data/repositories/wind_field_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// fetchSeries만 세는 가짜 직접호출 리포지토리(폴백 검증용).
class _FakeDirect implements WindFieldRepository {
  int seriesCalls = 0;

  @override
  Future<WindField> fetchField() async => throw UnimplementedError();

  @override
  Future<WindFieldSeries> fetchSeries({int hours = 48}) async {
    seriesCalls++;
    return WindFieldSeries(
      hourly: [
        WindField(
          time: DateTime(2026, 7, 21),
          minLat: 18,
          maxLat: 57,
          minLon: 108,
          maxLon: 148,
          latSteps: 2,
          lonSteps: 2,
          u: const [1, 1, 1, 1],
          v: const [0, 0, 0, 0],
        ),
      ],
    );
  }

  @override
  Future<List<PointWind>> fetchPointSeries(
    double lat,
    double lon, {
    int days = 16,
  }) async => const [];
}

/// 파일 포맷(base64 int16 cm/s)으로 인코딩한 JSON 문자열을 만든다.
String encodeFile({
  required int latSteps,
  required int lonSteps,
  required int steps,
  required int stepHours,
  required double Function(int s, int k) u,
  required double Function(int s, int k) v,
  List<int>? valid,
  List<double>? lats,
  List<double>? lons,
}) {
  final pts = latSteps * lonSteps;
  final ub = Int16List(steps * pts);
  final vb = Int16List(steps * pts);
  for (var s = 0; s < steps; s++) {
    for (var k = 0; k < pts; k++) {
      ub[s * pts + k] = (u(s, k) * 100).round();
      vb[s * pts + k] = (v(s, k) * 100).round();
    }
  }
  return jsonEncode({
    'fmt': lats != null || lons != null ? 2 : 1,
    'minLat': lats?.first ?? 18.0,
    'maxLat': lats?.last ?? 57.0,
    'minLon': lons?.first ?? 108.0,
    'maxLon': lons?.last ?? 148.0,
    'latSteps': latSteps,
    'lonSteps': lonSteps,
    if (lats != null) 'lats': lats,
    if (lons != null) 'lons': lons,
    'start': '2026-07-21T00:00',
    'stepHours': stepHours,
    'steps': steps,
    if (valid != null) 'valid': valid,
    'u': base64Encode(ub.buffer.asUint8List()),
    'v': base64Encode(vb.buffer.asUint8List()),
  });
}

void main() {
  test('parseWindFieldFile: 격자·시간축·값(cm/s 왕복)이 복원된다', () {
    final json =
        jsonDecode(
              encodeFile(
                latSteps: 3,
                lonSteps: 4,
                steps: 5,
                stepHours: 3,
                u: (s, k) => k.toDouble() - 5 + s,
                v: (s, k) => -k / 2,
              ),
            )
            as Map<String, dynamic>;
    final series = parseWindFieldFile(json);

    expect(series.length, 5);
    final f0 = series.hourly.first;
    expect(f0.latSteps, 3);
    expect(f0.lonSteps, 4);
    expect(f0.u, hasLength(12));
    // 3시간 간격이 시간축에 반영된다.
    expect(series.hourly[1].time.difference(f0.time), const Duration(hours: 3));
    // 값 왕복(0.01 이내).
    expect(f0.u[6], closeTo(1, 0.001)); // k=6 → 6-5+0 = 1
    expect(series.hourly[2].u[6], closeTo(3, 0.001)); // s=2 → +2
    expect(f0.v[4], closeTo(-2, 0.001)); // k=4 → -2
  });

  test('parseWindFieldFile: valid 없는 예전 파일은 전부 0인 스텝을 결측으로 '
      '표시하되 자르지는 않는다(최신 데이터 우선, 지도가 회색 처리)', () {
    // 6스텝 중 마지막 2스텝은 전부 0(예보 없는 날짜) — 길이는 6 그대로,
    // 마지막 2개만 hasData=false여야 한다.
    final json =
        jsonDecode(
              encodeFile(
                latSteps: 2,
                lonSteps: 2,
                steps: 6,
                stepHours: 3,
                u: (s, k) => s < 4 ? 3.0 : 0.0,
                v: (s, k) => s < 4 ? -1.0 : 0.0,
              ),
            )
            as Map<String, dynamic>;
    final series = parseWindFieldFile(json);
    expect(series.length, 6);
    for (var s = 0; s < 4; s++) {
      expect(series.hourly[s].hasData, isTrue, reason: 'step $s');
    }
    for (var s = 4; s < 6; s++) {
      expect(series.hourly[s].hasData, isFalse, reason: 'step $s');
    }
    // 값 자체는 여전히 실데이터가 들어 있다(잘리지 않았으므로).
    expect(series.hourly[3].u.first, closeTo(3, 0.001));
  });

  test('parseWindFieldFile: valid 배열이 있으면 그걸 그대로 hasData에 쓴다', () {
    final json =
        jsonDecode(
              encodeFile(
                latSteps: 2,
                lonSteps: 2,
                steps: 4,
                stepHours: 3,
                u: (s, k) => 5.0, // 전부 0이 아닌 값(휴리스틱과 무관함을 확인)
                v: (s, k) => 0.5,
                valid: [1, 1, 0, 0],
              ),
            )
            as Map<String, dynamic>;
    final series = parseWindFieldFile(json);
    expect(series.length, 4);
    expect(series.hourly[0].hasData, isTrue);
    expect(series.hourly[1].hasData, isTrue);
    expect(series.hourly[2].hasData, isFalse);
    expect(series.hourly[3].hasData, isFalse);
  });

  test('parseWindFieldFile: fmt 2(적응형 격자)의 lats/lons 배열을 그대로 '
      'WindField 축 좌표로 쓴다(균일 재구성 안 함)', () {
    // 비균일(적응형) 축: lat은 0,1,4(끝쪽으로 갈수록 넓어짐), lon은 10,11,13.
    const lats = [0.0, 1.0, 4.0];
    const lons = [10.0, 11.0, 13.0];
    final json =
        jsonDecode(
              encodeFile(
                latSteps: 3,
                lonSteps: 3,
                steps: 1,
                stepHours: 3,
                u: (s, k) => k.toDouble(),
                v: (s, k) => 0,
                lats: lats,
                lons: lons,
              ),
            )
            as Map<String, dynamic>;
    final series = parseWindFieldFile(json);
    final f0 = series.hourly.first;
    expect(f0.lats, lats);
    expect(f0.lons, lons);
    // 격자점 좌표에서는 보간 없이 그 값 그대로 나와야 한다.
    expect(f0.sample(0, 10)!.$1, closeTo(0, 0.001));
    expect(f0.sample(4, 13)!.$1, closeTo(8, 0.001));
  });

  test('서버 파일이 200이면 그걸 쓰고, 실패하면 direct로 폴백한다', () async {
    final body = encodeFile(
      latSteps: 2,
      lonSteps: 2,
      steps: 1,
      stepHours: 3,
      u: (_, _) => 7,
      v: (_, _) => 0,
    );
    // 첫 요청은 성공(서버 파일), 이후엔 404.
    var served = false;
    final client = MockClient((req) async {
      if (!served) {
        served = true;
        return http.Response(body, 200);
      }
      return http.Response('nope', 404);
    });

    final direct = _FakeDirect();
    final repo = GithubWindFieldRepository(
      direct: direct,
      client: client,
      url: 'https://example.test/wind_field.json.gz',
    );

    final fromServer = await repo.fetchSeries(hours: 3);
    expect(direct.seriesCalls, 0); // 서버 파일 성공 → direct 안 씀
    expect(fromServer.hourly.first.u.first, closeTo(7, 0.001));

    final fromDirect = await repo.fetchSeries(hours: 3);
    expect(direct.seriesCalls, 1); // 파일 실패 → direct 폴백
    expect(fromDirect.hourly.first.u.first, 1);
  });
}
