import 'dart:convert';

import 'package:bada_mobile/core/network/data_go_kr.dart';
import 'package:bada_mobile/core/storage/cache_store.dart';
import 'package:bada_mobile/features/fishing/data/models/fishing_index.dart';
import 'package:bada_mobile/features/fishing/data/repositories/data_go_kr_fishing_repository.dart';
import 'package:bada_mobile/features/fishing/data/repositories/mock_fishing_repository.dart';
import 'package:bada_mobile/features/locations/data/sample_locations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-07-16 실제 응답의 item 형식 그대로.
Map<String, dynamic> realItem({
  String point = '가거도',
  double lat = 34.07308,
  double lot = 125.08805,
  String slot = '오전',
  String species = '감성돔',
  String index = '좋음',
}) => {
  'seafsPstnNm': point,
  'lat': lat,
  'lot': lot,
  'predcYmd': '2026-07-16',
  'predcNoonSeCd': slot,
  'seafsTgfshNm': species,
  'tdlvHrCn': '대조기',
  'minWvhgt': 0.9,
  'maxWvhgt': 0.9,
  'minWtem': 25.30,
  'maxWtem': 25.40,
  'minArtmp': 25.6,
  'maxArtmp': 25.9,
  'minCrsp': 0.20,
  'maxCrsp': 0.60,
  'minWspd': 1.7,
  'maxWspd': 4.1,
  'totalIndex': index,
};

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

    test('28일(과거 2주~미래 2주) × 오전/오후 × 어종별 지수를 반환한다', () async {
      final forecast = await repo.fetchForecast(sampleLocations.first);
      // 이제 후보 어종 전체(fishingSpeciesCatalog)에 대해 생성한다 — 사용자가
      // 홈에서 어떤 어종을 골라도 지수가 보이도록.
      final n = fishingSpeciesCatalog.length;
      expect(forecast.indices, hasLength(28 * 2 * n));
      expect(forecast.forDate(DateTime.now()), hasLength(2 * n));
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

    test('response 래퍼 없는 JSON 축약형 봉투도 처리한다 (실측 형태)', () {
      final body = jsonEncode({
        'header': {'resultCode': '00', 'resultMsg': 'NORMAL_SERVICE'},
        'body': {
          'items': {
            'item': [
              {'lot': 126.56305, 'lat': 35.97555},
            ],
          },
          'totalCount': 1,
        },
      });
      expect(parseDataGoKrItems(body), hasLength(1));
    });

    test('NODATA_ERROR(03)는 빈 목록을 돌려준다', () {
      final body = jsonEncode({
        'header': {'resultCode': '03', 'resultMsg': 'NODATA_ERROR'},
      });
      expect(parseDataGoKrItems(body), isEmpty);
    });
  });

  group('mapFishingItem (실측 필드)', () {
    test('실제 응답 형식을 FishingIndex로 변환한다', () {
      final index = mapFishingItem(realItem());
      expect(index.date, DateTime(2026, 7, 16));
      expect(index.timeSlot, '오전');
      expect(index.grade, FishingGrade.good);
      expect(index.species, '감성돔');
      expect(index.pointName, '가거도');
      expect(index.tidePhase, '대조기');
      expect(index.waveHeightM, closeTo(0.9, 0.001));
      expect(index.waterTempC, closeTo(25.35, 0.001));
    });
  });

  group('DataGoKrFishingRepository', () {
    // 날짜별 원본 캐시가 static이라 테스트끼리 새어 나간다. 매번 비우고 시작한다.
    setUp(DataGoKrFishingRepository.clearMemoryCache);

    test('가장 가까운 포인트를 골라 어종별 지수를 돌려준다', () async {
      final client = MockClient((request) async {
        expect(
          request.url.path,
          '/1192136/fcstFishingv2/GetFcstFishingApiServicev2',
        );
        expect(request.url.queryParameters['gubun'], '갯바위');
        expect(request.url.queryParameters['type'], 'json');
        return http.Response(
          jsonEncode({
            'header': {'resultCode': '00', 'resultMsg': 'NORMAL_SERVICE'},
            'body': {
              'items': {
                'item': [
                  // 제주에서 먼 포인트(가거도)와 가까운 포인트(김녕).
                  realItem(),
                  realItem(slot: '오후', index: '보통'),
                  realItem(point: '김녕', lat: 33.558, lot: 126.758),
                  realItem(
                    point: '김녕',
                    lat: 33.558,
                    lot: 126.758,
                    slot: '오후',
                    index: '매우좋음',
                  ),
                  realItem(
                    point: '김녕',
                    lat: 33.558,
                    lot: 126.758,
                    species: '참돔',
                  ),
                ],
              },
              'totalCount': 5,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final jeju = sampleLocations.firstWhere((l) => l.id == 'jeju');
      final repo = DataGoKrFishingRepository(
        client: client,
        serviceKey: 'test-key',
      );
      final forecast = await repo.fetchForecast(jeju);

      expect(forecast.indices, hasLength(3)); // 김녕 3건만
      expect(forecast.indices.every((i) => i.pointName == '김녕'), isTrue);

      final rep = forecast.representativeForDate(DateTime(2026, 7, 16));
      expect(rep, hasLength(2)); // 감성돔 오전/오후
      expect(rep.first.timeSlot, '오전');
      expect(rep.last.grade, FishingGrade.veryGood);
    });

    test('지역을 바꿔도 전국 원본은 한 번만 받는다', () async {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return _nationwideResponse();
      });
      final repo = DataGoKrFishingRepository(
        client: client,
        serviceKey: 'test-key',
      );

      final jeju = sampleLocations.firstWhere((l) => l.id == 'jeju');
      final other = sampleLocations.firstWhere((l) => l.id != 'jeju');
      await repo.fetchForecast(jeju);
      await repo.fetchForecast(other);
      await repo.fetchForecast(jeju);

      // 지역마다 다시 받으면 지역을 바꿀 때마다 몇 초씩 기다리게 된다.
      expect(calls, 1);
    });

    test('디스크 캐시가 있으면 네트워크를 타지 않는다', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = CacheStore(await SharedPreferences.getInstance());
      final jeju = sampleLocations.firstWhere((l) => l.id == 'jeju');

      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return _nationwideResponse();
      });
      await DataGoKrFishingRepository(
        client: client,
        serviceKey: 'test-key',
        cache: cache,
      ).fetchForecast(jeju);
      expect(calls, 1);

      // 저장은 일부러 await하지 않으므로(화면을 먼저 그리려고) 여기서 기다린다.
      for (var i = 0; i < 100 && cache.readString(_dayKey()) == null; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(cache.readString(_dayKey()), isNotNull);

      // 앱을 껐다 켠 상황: 메모리 캐시는 비었지만 디스크에는 남아 있다.
      DataGoKrFishingRepository.clearMemoryCache();
      final offline = MockClient(
        (_) async => throw http.ClientException('오프라인'),
      );
      final forecast = await DataGoKrFishingRepository(
        client: offline,
        serviceKey: 'test-key',
        cache: cache,
      ).fetchForecast(jeju);

      expect(forecast.indices, isNotEmpty);
      expect(forecast.indices.every((i) => i.pointName == '김녕'), isTrue);
    });
  });

  group('slimFishingItems', () {
    test('쓰지 않는 필드를 버려 캐시 크기를 줄인다', () {
      final body = jsonEncode({
        'header': {'resultCode': '00', 'resultMsg': 'NORMAL_SERVICE'},
        'body': {
          'items': {
            'item': [
              {...realItem(), 'rowNum': 1, 'useless': 'x' * 500},
            ],
          },
          'totalCount': 1,
        },
      });
      final slim = slimFishingItems(body);

      expect(slim, hasLength(1));
      expect(slim.first.containsKey('useless'), isFalse);
      expect(slim.first.containsKey('rowNum'), isFalse);
      // 남긴 필드만으로 기존 변환이 그대로 동작해야 한다.
      final index = mapFishingItem(slim.first);
      expect(index.pointName, '가거도');
      expect(index.grade, FishingGrade.good);
    });
  });
}

/// 오늘 날짜의 전국 원본 캐시 키(리포지토리가 쓰는 것과 같은 규칙).
String _dayKey() {
  final n = DateTime.now();
  return 'fishing_day_${n.year}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.day.toString().padLeft(2, '0')}';
}

/// 가거도·김녕 두 포인트가 섞인 전국 응답(형식은 실제 응답과 같다).
http.Response _nationwideResponse() => http.Response(
  jsonEncode({
    'header': {'resultCode': '00', 'resultMsg': 'NORMAL_SERVICE'},
    'body': {
      'items': {
        'item': [realItem(), realItem(point: '김녕', lat: 33.558, lot: 126.758)],
      },
      'totalCount': 2,
    },
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
