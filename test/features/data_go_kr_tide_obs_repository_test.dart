import 'dart:convert';
import 'dart:math' as math;

import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:bada_mobile/features/tide/data/repositories/data_go_kr_tide_obs_repository.dart';
import 'package:bada_mobile/features/tide/data/repositories/mock_tide_repository.dart';
import 'package:bada_mobile/features/tide/data/repositories/tide_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 반일주조(주기 12시간) 합성 조위. 시각의 절대시(ms)로만 정해져 자정 경계에서
/// 연속이다. 평균 400cm, 진폭 300cm.
double _level(DateTime dt) =>
    400 +
    300 * math.cos(2 * math.pi * (dt.millisecondsSinceEpoch / 3600000) / 12);

String _fmt(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-'
    '${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:00:00';

void main() {
  final incheon = sampleLocations.firstWhere((l) => l.id == 'incheon');

  /// 바다누리식 봉투(result.data)로 하루치 1시간 간격 예측 조위를 돌려준다.
  /// pre_value(예측)와 tide_level(실측)을 함께 넣어 **예측 우선** 선택을 검증한다.
  MockClient client() => MockClient((request) async {
    expect(request.url.host, 'www.khoa.go.kr');
    expect(request.url.path, '/api/oceangrid/tideObsPreTab/search.do');
    expect(request.url.queryParameters['ObsCode'], 'DT_0001');
    expect(request.url.queryParameters['ResultType'], 'json');
    final ymd = request.url.queryParameters['Date']!;
    final d = DateTime(
      int.parse(ymd.substring(0, 4)),
      int.parse(ymd.substring(4, 6)),
      int.parse(ymd.substring(6)),
    );
    final items = [
      for (var h = 0; h < 24; h++)
        {
          'record_time': _fmt(d.add(Duration(hours: h))),
          'pre_value': _level(d.add(Duration(hours: h))).toStringAsFixed(1),
          'tide_level': '0', // 실측은 0 — 곡선이 예측을 쓰는지 확인용
        },
    ];
    return http.Response(
      jsonEncode({
        'result': {
          'meta': {'obs_post_id': 'DT_0001', 'obs_post_name': '인천'},
          'data': items,
        },
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  group('DataGoKrTideObsRepository', () {
    final date = DateTime.now().add(const Duration(days: 3));
    final day = DateTime(date.year, date.month, date.day);

    test('예측 조위 시계열로 25개 시간별 곡선을 만든다(예측 우선)', () async {
      final repo = DataGoKrTideObsRepository(
        client: client(),
        serviceKey: 'test-key',
      );
      final tide = await repo.fetchTideDay(incheon, date);

      expect(tide.hourlyHeightsCm, hasLength(25));
      // 실측(0)이 아니라 예측(pre_value)을 썼는지 — 정시값이 합성곡선과 일치.
      for (final h in [0, 6, 12, 18, 24]) {
        expect(
          tide.hourlyHeightsCm[h],
          closeTo(_level(day.add(Duration(hours: h))), 0.5),
        );
      }
    });

    test('시계열의 국소 극값을 만조/간조로 뽑고 시각을 정밀화한다', () async {
      final repo = DataGoKrTideObsRepository(
        client: client(),
        serviceKey: 'test-key',
      );
      final tide = await repo.fetchTideDay(incheon, date);

      // 주기 12시간 → 하루 만조 2·간조 2 안팎.
      expect(tide.extremes.length, inInclusiveRange(3, 5));
      // 만조/간조가 번갈아 나오고, 모든 극값이 당일 안·진폭 범위 안.
      for (var i = 0; i < tide.extremes.length; i++) {
        final e = tide.extremes[i];
        expect(e.time.isBefore(day), isFalse);
        expect(e.time.isBefore(day.add(const Duration(days: 1))), isTrue);
        expect(e.heightCm, inInclusiveRange(95.0, 705.0));
        if (i > 0) {
          expect(e.isHigh, isNot(tide.extremes[i - 1].isHigh));
        }
      }
      // 만조는 700 근처, 간조는 100 근처(포물선 보간이 정시 격자 꼭짓점 근사).
      final high = tide.extremes.firstWhere((e) => e.isHigh);
      final low = tide.extremes.firstWhere((e) => !e.isHigh);
      expect(high.heightCm, greaterThan(650));
      expect(low.heightCm, lessThan(150));
    });

    test('관측소 코드가 없으면 예외 → 폴백 래퍼에서 합성 데이터로 정상 조회', () async {
      final noCode = sampleLocations.firstWhere(
        (l) => l.khoaStationCode == null,
      );
      final repo = TideRepository.withFallback(
        primary: DataGoKrTideObsRepository(
          client: client(),
          serviceKey: 'test-key',
        ),
        fallback: MockTideRepository(),
      );
      final tide = await repo.fetchTideDay(noCode, DateTime.now());
      expect(tide.hourlyHeightsCm, hasLength(25));
    });
  });
}
