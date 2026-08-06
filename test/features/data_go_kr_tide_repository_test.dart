import 'dart:convert';

import 'package:bada_mobile/features/locations/data/models/sea_location.dart';
import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:bada_mobile/features/tide/data/models/tide_data.dart';
import 'package:bada_mobile/features/tide/data/repositories/data_go_kr_tide_repository.dart';
import 'package:bada_mobile/features/tide/data/repositories/mock_tide_repository.dart';
import 'package:bada_mobile/features/tide/data/repositories/tide_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _body(List<Map<String, dynamic>> items) => jsonEncode({
  'response': {
    'header': {'resultCode': '00', 'resultMsg': 'NORMAL SERVICE'},
    'body': {
      'items': {'item': items},
    },
  },
});

void main() {
  final incheon = sampleLocations.firstWhere((l) => l.id == 'incheon');

  group('mapTideItem 필드 후보 매핑', () {
    test('실측 응답 형식 (predcDt/predcTdlvVl/extrSe)', () {
      // 2026-07-16 인천 실제 응답 그대로.
      final high = mapTideItem({
        'obsvtrNm': '인천',
        'lot': 126.59222,
        'lat': 37.45194,
        'predcDt': '2026-07-16 06:11',
        'predcTdlvVl': 949.0,
        'extrSe': '1',
      });
      expect(high.time, DateTime(2026, 7, 16, 6, 11));
      expect(high.heightCm, 949.0);
      expect(high.isHigh, isTrue);

      final low = mapTideItem({
        'predcDt': '2026-07-16 12:38',
        'predcTdlvVl': 109.0,
        'extrSe': '4',
      });
      expect(low.isHigh, isFalse);

      final secondHigh = mapTideItem({
        'predcDt': '2026-07-16 18:24',
        'predcTdlvVl': 838.0,
        'extrSe': '3',
      });
      expect(secondHigh.isHigh, isTrue);
    });

    test('camelCase(tphTime/tphHght/hlCode) 형식', () {
      final e = mapTideItem({
        'tphTime': '2026-07-20 04:12:00',
        'tphHght': '742',
        'hlCode': '고조',
      });
      expect(e.time, DateTime(2026, 7, 20, 4, 12));
      expect(e.heightCm, 742);
      expect(e.isHigh, isTrue);
    });

    test('snake_case(record_time/tide_level/hl_code) 형식', () {
      final e = mapTideItem({
        'record_time': '2026-07-20 10:40:00',
        'tide_level': '92',
        'hl_code': '저조',
      });
      expect(e.isHigh, isFalse);
      expect(e.heightCm, 92);
    });

    test('H/L 코드도 인식한다', () {
      expect(
        mapTideItem({
          'tphTime': '2026-07-20 04:12:00',
          'tphHght': '1',
          'hlCode': 'H',
        }).isHigh,
        isTrue,
      );
    });

    test('알 수 없는 필드 구성은 FormatException (→ 폴백 트리거)', () {
      expect(() => mapTideItem({'foo': 1, 'bar': 2}), throwsFormatException);
    });
  });

  group('interpolateHourlyHeights (코사인 보간)', () {
    final day = DateTime(2026, 7, 20);
    final extremes = [
      TideExtreme(
        time: DateTime(2026, 7, 19, 22),
        heightCm: 100,
        isHigh: false,
      ),
      TideExtreme(time: DateTime(2026, 7, 20, 4), heightCm: 700, isHigh: true),
      TideExtreme(
        time: DateTime(2026, 7, 20, 10),
        heightCm: 120,
        isHigh: false,
      ),
      TideExtreme(time: DateTime(2026, 7, 20, 16), heightCm: 680, isHigh: true),
      TideExtreme(
        time: DateTime(2026, 7, 20, 22),
        heightCm: 110,
        isHigh: false,
      ),
      TideExtreme(time: DateTime(2026, 7, 21, 4), heightCm: 690, isHigh: true),
    ];

    test('25개 값을 만들고 극값 시각에서 극값과 일치한다', () {
      final hourly = interpolateHourlyHeights(extremes, day);
      expect(hourly, hasLength(25));
      expect(hourly[4], closeTo(700, 0.01)); // 04시 만조
      expect(hourly[10], closeTo(120, 0.01)); // 10시 간조
      expect(hourly[16], closeTo(680, 0.01)); // 16시 만조
    });

    test('모든 값이 극값 범위 안에 있다', () {
      final hourly = interpolateHourlyHeights(extremes, day);
      for (final h in hourly) {
        expect(h, inInclusiveRange(100, 700));
      }
    });
  });

  group('DataGoKrTideRepository', () {
    MockClient client({bool camel = true}) => MockClient((request) async {
      expect(request.url.host, 'apis.data.go.kr');
      expect(
        request.url.path,
        '/1192136/tideFcstHghLw/GetTideFcstHghLwApiService',
      );
      expect(request.url.queryParameters['obsCode'], 'DT_0001');
      expect(request.url.queryParameters['type'], 'json');
      final ymd = request.url.queryParameters['reqDate']!;
      final date = DateTime.parse(ymd);
      String t(int hour) =>
          '${ymd.substring(0, 4)}-${ymd.substring(4, 6)}-${ymd.substring(6)} '
          '${hour.toString().padLeft(2, '0')}:00:00';
      List<Map<String, dynamic>> items;
      if (camel) {
        items = [
          {'tphTime': t(2), 'tphHght': '${100 + date.day}', 'hlCode': '저조'},
          {'tphTime': t(8), 'tphHght': '700', 'hlCode': '고조'},
          {'tphTime': t(14), 'tphHght': '110', 'hlCode': '저조'},
          {'tphTime': t(20), 'tphHght': '690', 'hlCode': '고조'},
        ];
      } else {
        items = [
          {'record_time': t(8), 'tide_level': '700', 'hl_code': '고조'},
          {'record_time': t(14), 'tide_level': '110', 'hl_code': '저조'},
        ];
      }
      return http.Response(
        _body(items),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });

    test('3일치(전/당/익일)를 조회해 당일 극값과 25개 시간별 조위를 만든다', () async {
      final repo = DataGoKrTideRepository(
        client: client(),
        serviceKey: 'test-key',
      );
      final date = DateTime.now().add(const Duration(days: 3));
      final tide = await repo.fetchTideDay(incheon, date);

      expect(tide.extremes, hasLength(4));
      expect(tide.extremes.first.isHigh, isFalse);
      expect(tide.extremes[1].isHigh, isTrue);
      expect(tide.hourlyHeightsCm, hasLength(25));
      // 08시 만조 700cm이 곡선에 반영됐는지
      expect(tide.hourlyHeightsCm[8], closeTo(700, 0.01));
    });

    test('당일만 비어 오면 실패로 쳐서 폴백으로 넘긴다', () async {
      // **2026-08-06 사용자 제보 재현.** 전날·다음날은 정상인데 당일 응답만
      // 비어 오면(간헐적 응답 실패), 예전엔 이걸 성공으로 올렸다. 그러면
      // 화면에 만조·간조 카드가 하나도 없고, 조위 곡선은 마지막 극값으로
      // 25시간 내내 고정돼 조류세기가 0%로 뜬다.
      final date = DateTime.now().add(const Duration(days: 3));
      String ymdOf(DateTime d) =>
          '${d.year}'
          '${d.month.toString().padLeft(2, '0')}'
          '${d.day.toString().padLeft(2, '0')}';
      final today = ymdOf(DateTime(date.year, date.month, date.day));

      final holeyClient = MockClient((request) async {
        final ymd = request.url.queryParameters['reqDate']!;
        // 당일만 빈 목록으로 답한다(HTTP는 200 정상).
        if (ymd == today) return http.Response(_body(const []), 200);
        return http.Response(
          _body([
            {
              'obsvtrNm': '인천',
              'predcDt':
                  '${ymd.substring(0, 4)}-${ymd.substring(4, 6)}-'
                  '${ymd.substring(6)} 08:00',
              'predcTdlvVl': 700.0,
              'extrSe': '1',
            },
          ]),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final repo = DataGoKrTideRepository(
        client: holeyClient,
        serviceKey: 'test-key',
      );
      expect(
        () => repo.fetchTideDay(incheon, date),
        throwsA(isA<FormatException>()),
        reason: '당일 극값이 없는데 성공으로 올리면 빈 물때 화면이 나온다',
      );
    });

    test('바다누리식 봉투(result.data)와 tph_level 필드도 처리한다', () async {
      final khoaClient = MockClient((request) async {
        final ymd = request.url.queryParameters['reqDate']!;
        String t(int hour) =>
            '${ymd.substring(0, 4)}-${ymd.substring(4, 6)}-${ymd.substring(6)} '
            '${hour.toString().padLeft(2, '0')}:00:00';
        return http.Response(
          jsonEncode({
            'result': {
              'meta': {'obs_post_id': 'DT_0001'},
              'data': [
                {'tph_time': t(5), 'tph_level': '705', 'hl_code': '고조'},
                {'tph_time': t(11), 'tph_level': '95', 'hl_code': '저조'},
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final repo = DataGoKrTideRepository(
        client: khoaClient,
        serviceKey: 'test-key',
      );
      final tide = await repo.fetchTideDay(
        incheon,
        DateTime.now().add(const Duration(days: 3)),
      );
      expect(tide.extremes, hasLength(2));
      expect(tide.extremes.first.heightCm, 705);
      expect(tide.hourlyHeightsCm[5], closeTo(705, 0.01));
    });

    test('다지점(khoaStationCodes) 지점은 첫 관측소로 폴백 조회한다', () async {
      // 실측·예측(1차) 실패 시 이 고저조(2차)가 다지점 지점도 받아줘야
      // 합성으로 직행하지 않는다(무창포 합성 표시 회귀 방지).
      const multi = SeaLocation(
        id: 'multi',
        name: '다지점',
        region: '서해',
        latitude: 36.2,
        longitude: 126.5,
        khoaStationCodes: ['DT_0001', 'DT_0099'],
      );
      final repo = DataGoKrTideRepository(
        client: client(),
        serviceKey: 'test-key',
      );
      final tide = await repo.fetchTideDay(
        multi,
        DateTime.now().add(const Duration(days: 3)),
      );
      expect(tide.extremes, isNotEmpty);
      expect(tide.hourlyHeightsCm, hasLength(25));
    });

    test('관측소 코드가 없는 지점은 예외를 던진다', () async {
      final noCode = sampleLocations.firstWhere(
        (l) => l.khoaStationCode == null,
      );
      final repo = DataGoKrTideRepository(
        client: client(),
        serviceKey: 'test-key',
      );
      expect(
        () => repo.fetchTideDay(noCode, DateTime.now()),
        throwsA(anything),
      );
    });

    test('관측소 코드가 없어도 폴백 래퍼에서는 합성 데이터로 정상 조회된다', () async {
      final noCode = sampleLocations.firstWhere(
        (l) => l.khoaStationCode == null,
      );
      final repo = TideRepository.withFallback(
        primary: DataGoKrTideRepository(
          client: client(),
          serviceKey: 'test-key',
        ),
        fallback: MockTideRepository(),
      );
      // 코드 없음은 DataRangeException이 아니라 일반 예외라 폴백을 타야 한다.
      final tide = await repo.fetchTideDay(noCode, DateTime.now());
      expect(tide.hourlyHeightsCm, hasLength(25));
    });
  });
}
