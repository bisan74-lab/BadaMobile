import 'dart:convert';

import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:bada_mobile/features/tide/data/models/tide_data.dart';
import 'package:bada_mobile/features/tide/data/repositories/data_go_kr_tide_repository.dart';
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
      expect(request.url.path, '/1192136/tideFcstHghLw/getTideFcstHghLw');
      expect(request.url.queryParameters['obsCode'], 'DT_0001');
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
  });
}
