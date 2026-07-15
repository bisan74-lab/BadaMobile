import 'dart:convert';

import 'package:bada_mobile/core/network/data_go_kr.dart';
import 'package:bada_mobile/features/fishing/data/models/fishing_index.dart';
import 'package:bada_mobile/features/fishing/data/repositories/mock_fishing_repository.dart';
import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FishingGrade', () {
    test('점수 ↔ 등급 매핑', () {
      expect(FishingGrade.fromScore(1), FishingGrade.veryBad);
      expect(FishingGrade.fromScore(5), FishingGrade.veryGood);
      expect(FishingGrade.fromScore(9), FishingGrade.veryGood); // clamp
      expect(FishingGrade.fromLabel('좋음'), FishingGrade.good);
      expect(FishingGrade.fromLabel('알수없음'), FishingGrade.normal); // 기본값
    });
  });

  group('MockFishingRepository', () {
    final repo = MockFishingRepository();

    test('7일 × 오전/오후 지수를 반환한다', () async {
      final forecast = await repo.fetchForecast(sampleLocations.first);
      expect(forecast.indices, hasLength(7 * 2));
      expect(forecast.forDate(DateTime.now()), hasLength(2));
      for (final i in forecast.indices) {
        expect(i.grade.score, inInclusiveRange(1, 5));
      }
    });
  });

  group('parseDataGoKrItems (공통 응답 봉투)', () {
    test('정상 응답에서 item 목록을 꺼낸다', () {
      final body = jsonEncode({
        'response': {
          'header': {'resultCode': '00', 'resultMsg': 'NORMAL SERVICE'},
          'body': {
            'items': {
              'item': [
                {'a': 1},
                {'a': 2},
              ],
            },
          },
        },
      });
      expect(parseDataGoKrItems(body), hasLength(2));
    });

    test('단일 item(리스트가 아닌 객체)도 처리한다', () {
      final body = jsonEncode({
        'response': {
          'header': {'resultCode': '00'},
          'body': {
            'items': {
              'item': {'a': 1},
            },
          },
        },
      });
      expect(parseDataGoKrItems(body), hasLength(1));
    });

    test('오류 resultCode는 예외를 던진다', () {
      final body = jsonEncode({
        'response': {
          'header': {
            'resultCode': '30',
            'resultMsg': 'SERVICE_KEY_IS_NOT_REGISTERED_ERROR',
          },
        },
      });
      expect(() => parseDataGoKrItems(body), throwsFormatException);
    });
  });
}
