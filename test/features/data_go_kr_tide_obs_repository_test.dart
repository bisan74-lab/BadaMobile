import 'dart:convert';
import 'dart:math' as math;

import 'package:bada_mobile/features/locations/data/models/sea_location.dart';
import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:bada_mobile/features/tide/data/repositories/data_go_kr_tide_obs_repository.dart';
import 'package:bada_mobile/features/tide/data/repositories/mock_tide_repository.dart';
import 'package:bada_mobile/features/tide/data/repositories/tide_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 테스트용 관측소 정의: 좌표 + 진폭 + 위상(시간 지연 h).
class _St {
  const _St(this.lat, this.lon, this.amp, this.shiftH);
  final double lat, lon, amp, shiftH;
}

const _stations = {
  'DT_0001': _St(37.45194, 126.59222, 300, 0), // 인천(단일 테스트용)
  'DT_A': _St(36.40, 126.49, 300, 0), // 북쪽
  'DT_B': _St(36.13, 126.51, 300, 0.6667), // 남쪽, 만조 40분 늦음
};

/// 반일주조(주기 12h) 합성 조위. 절대시(ms) 기준이라 자정 경계 연속.
double _level(DateTime dt, _St s) =>
    400 +
    s.amp *
        math.cos(
          2 * math.pi * (dt.millisecondsSinceEpoch / 3600000 - s.shiftH) / 12,
        );

String _fmt(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:'
    '${t.minute.toString().padLeft(2, '0')}';

/// obsCode별로 해당 관측소의 좌표·위상으로 시계열을 돌려주는 MockClient
/// (활용가이드 SV-AP-02-009 응답 봉투 그대로).
MockClient _client() => MockClient((request) async {
  expect(request.url.host, 'apis.data.go.kr');
  expect(
    request.url.path,
    '/1192136/surveyTideLevel/GetSurveyTideLevelApiService',
  );
  final code = request.url.queryParameters['obsCode']!;
  final st = _stations[code]!;
  final step = int.parse(request.url.queryParameters['min']!);
  final ymd = request.url.queryParameters['reqDate']!;
  final d = DateTime(
    int.parse(ymd.substring(0, 4)),
    int.parse(ymd.substring(4, 6)),
    int.parse(ymd.substring(6)),
  );
  final items = [
    for (var m = 0; m < 1440; m += step)
      // 매시 정각 행은 조위를 null로 깨뜨려 결측 내성(행 건너뜀)을 함께
      // 검증한다 — 10분 격자에서 6행 중 1행 결측이어도 곡선·극값은 유지된다.
      if (m % 60 == 0)
        {
          'obsvtrNm': code,
          'lat': st.lat,
          'lot': st.lon,
          'obsrvnDt': _fmt(d.add(Duration(minutes: m))),
          'bscTdlvHgt': null,
          'tdlvHgt': null,
        }
      else
        {
          'obsvtrNm': code,
          'lat': st.lat,
          'lot': st.lon,
          'obsrvnDt': _fmt(d.add(Duration(minutes: m))),
          'bscTdlvHgt': 0,
          'tdlvHgt': double.parse(
            _level(d.add(Duration(minutes: m)), st).toStringAsFixed(1),
          ),
        },
  ];
  return http.Response(
    jsonEncode({
      'response': {
        'header': {'resultCode': '00', 'resultMsg': 'NORMAL_SERVICE'},
        'body': {
          'items': {'item': items},
          'totalCount': items.length,
          'type': 'json',
        },
      },
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
});

void main() {
  final incheon = sampleLocations.firstWhere((l) => l.id == 'incheon');
  final date = DateTime.now().add(const Duration(days: 3));
  final day = DateTime(date.year, date.month, date.day);

  DataGoKrTideObsRepository repo() =>
      DataGoKrTideObsRepository(client: _client(), serviceKey: 'test-key');

  /// 정오 부근 만조 시각.
  DateTime highNearNoon(List extremes) {
    final noon = day.add(const Duration(hours: 12));
    final highs = extremes.where((e) => e.isHigh).toList()
      ..sort(
        (a, b) => a.time
            .difference(noon)
            .abs()
            .compareTo(b.time.difference(noon).abs()),
      );
    return highs.first.time as DateTime;
  }

  group('단일 관측소', () {
    test('예측 조위 시계열로 25개 곡선을 만든다(예측 우선)', () async {
      final tide = await repo().fetchTideDay(incheon, date);
      expect(tide.hourlyHeightsCm, hasLength(25));
      // 정각 행은 결측(위 MockClient)이라 이웃 10분 값으로 보간된다 —
      // ±2cm면 "실측 0이 아니라 예측 곡선을 쓴다"는 검증에 충분하다.
      for (final h in [0, 6, 12, 18, 24]) {
        expect(
          tide.hourlyHeightsCm[h],
          closeTo(
            _level(day.add(Duration(hours: h)), _stations['DT_0001']!),
            2.0,
          ),
        );
      }
    });

    test('국소 극값을 만조/간조로 뽑아 정밀화한다', () async {
      final tide = await repo().fetchTideDay(incheon, date);
      expect(tide.extremes.length, inInclusiveRange(3, 5));
      final high = tide.extremes.firstWhere((e) => e.isHigh);
      final low = tide.extremes.firstWhere((e) => !e.isHigh);
      expect(high.heightCm, greaterThan(690));
      expect(low.heightCm, lessThan(110));
    });

    test('코드 없으면 예외 → 폴백 래퍼에서 합성 데이터', () async {
      final noCode = sampleLocations.firstWhere(
        (l) => l.tideStationCodes.isEmpty,
      );
      final r = TideRepository.withFallback(
        primary: repo(),
        fallback: MockTideRepository(),
      );
      final tide = await r.fetchTideDay(noCode, DateTime.now());
      expect(tide.hourlyHeightsCm, hasLength(25));
    });
  });

  group('다지점 거리가중 보간', () {
    // 두 관측소(A 북쪽·B 남쪽) 사이, A에 더 가까운 지점.
    SeaLocation loc(List<String> codes) => SeaLocation(
      id: 'target',
      name: '보간지점',
      region: '서해',
      latitude: 36.30,
      longitude: 126.51,
      khoaStationCodes: codes,
    );

    test('보간 만조 시각이 두 관측소 사이이고 가까운 쪽(A)에 치우친다', () async {
      final tideA = await repo().fetchTideDay(loc(['DT_A']), date);
      final tideB = await repo().fetchTideDay(loc(['DT_B']), date);
      final tideAB = await repo().fetchTideDay(loc(['DT_A', 'DT_B']), date);

      final tA = highNearNoon(tideA.extremes);
      final tB = highNearNoon(tideB.extremes);
      final tAB = highNearNoon(tideAB.extremes);

      // B는 A보다 만조가 늦다(위상 +40분).
      expect(tB.isAfter(tA), isTrue);
      // 보간값은 A와 B 사이.
      expect(tAB.isAfter(tA), isTrue);
      expect(tAB.isBefore(tB), isTrue);
      // A가 더 가까우니 A쪽에 치우친다(중점보다 A에 가깝다).
      final toA = tAB.difference(tA).abs();
      final toB = tB.difference(tAB).abs();
      expect(toA < toB, isTrue);
    });

    test('보간 조위는 위상차에도 진폭이 유지된다(곡선 평균 아님)', () async {
      final tideAB = await repo().fetchTideDay(loc(['DT_A', 'DT_B']), date);
      final high = tideAB.extremes.firstWhere((e) => e.isHigh);
      // 두 관측소 만조가 모두 ~700이므로 보간 만조도 ~700 근처여야 한다
      // (곡선을 평균했다면 위상차로 690 밑으로 깎였을 것).
      expect(high.heightCm, greaterThan(690));
      expect(tideAB.hourlyHeightsCm, hasLength(25));
    });
  });

  group('2차항 보정(시간차·조위비)', () {
    SeaLocation loc({int offsetMin = 0, double scale = 1.0}) => SeaLocation(
      id: 'calib',
      name: '보정지점',
      region: '남해',
      latitude: 37.45194,
      longitude: 126.59222,
      khoaStationCode: 'DT_0001',
      tideTimeOffsetMin: offsetMin,
      tideHeightScale: scale,
    );

    test('만조/간조 시각이 오프셋만큼 늦어지고 조위가 배율만큼 커진다', () async {
      final base = await repo().fetchTideDay(loc(), date);
      final adj = await repo().fetchTideDay(
        loc(offsetMin: 12, scale: 1.05),
        date,
      );

      final baseHigh = highNearNoon(base.extremes);
      final adjHigh = highNearNoon(adj.extremes);
      // 10분 격자 + 포물선 정밀화라 ±수 분 오차 허용.
      final shiftMin = adjHigh.difference(baseHigh).inMinutes;
      expect(shiftMin, inInclusiveRange(7, 17));

      final baseTop = base.extremes.firstWhere((e) => e.isHigh).heightCm;
      final adjTop = adj.extremes.firstWhere((e) => e.isHigh).heightCm;
      expect(adjTop / baseTop, closeTo(1.05, 0.01));
    });
  });
}
