import 'dart:convert';
import 'dart:io' show gzip;

import 'package:bada_mobile/core/storage/cache_store.dart';
import 'package:bada_mobile/features/fishing/data/models/fishing_index.dart';
import 'package:bada_mobile/features/fishing/data/repositories/fishing_repository.dart';
import 'package:bada_mobile/features/fishing/data/repositories/github_fishing_repository.dart';
import 'package:bada_mobile/features/locations/data/models/sea_location.dart';
import 'package:bada_mobile/features/tide/presentation/tide_screen.dart'
    show seasonalSpecies;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `tool/fetch_fishing.py`가 만드는 것과 같은 구조의 표본 파일.
/// 포인트 두 곳(가거도=서남해 먼바다, 김녕=제주 북동)만 담는다.
String sampleFile() => jsonEncode({
  'fmt': 1,
  'generated': '2026-08-01T09:00:00Z',
  'points': [
    {'n': '가거도', 'la': 34.073, 'lo': 125.088},
    {'n': '김녕', 'la': 33.558, 'lo': 126.758},
  ],
  'dates': ['2026-08-01', '2026-08-02'],
  'species': ['감성돔', '우럭'],
  'tides': ['대조기'],
  'slots': ['오전', '오후'],
  // [포인트, 날짜, 오전/오후, 어종, 등급, 파고m, 수온C, 물때]
  'rows': [
    [0, 0, 0, 0, '나쁨', 1.2, 24.0, 0],
    [1, 0, 0, 0, '좋음', 0.9, 25.3, 0],
    [1, 0, 1, 0, '매우좋음', 0.8, 25.5, 0],
    [1, 0, 0, 1, '보통', 0.9, 25.3, 0],
    [1, 1, 0, 0, '매우나쁨', 1.5, 25.1, 0],
  ],
});

/// 실패만 하는 폴백(서버 파일 경로가 실제로 쓰였는지 확인용).
class _NeverRepository implements FishingRepository {
  int calls = 0;
  @override
  Future<FishingForecast> fetchForecast(SeaLocation location) async {
    calls++;
    throw StateError('직접 호출로 내려가면 안 된다');
  }
}

/// 정해진 결과를 돌려주는 폴백.
class _StubRepository implements FishingRepository {
  int calls = 0;
  @override
  Future<FishingForecast> fetchForecast(SeaLocation location) async {
    calls++;
    return FishingForecast(locationId: location.id, indices: const []);
  }
}

const _jeju = SeaLocation(
  id: 'jeju',
  name: '제주',
  region: '제주',
  latitude: 33.50,
  longitude: 126.75,
);
const _far = SeaLocation(
  id: 'gageo',
  name: '가거도',
  region: '서해',
  latitude: 34.07,
  longitude: 125.09,
);

void main() {
  setUp(GithubFishingRepository.clearMemoryCache);

  group('parseFishingIndexFile', () {
    test('색인 기반 행을 지수 목록으로 되돌린다', () {
      final file = parseFishingIndexFile(sampleFile());

      expect(file.points, hasLength(2));
      expect(file.generated, DateTime.utc(2026, 8, 1, 9));

      final kimnyeong = file.indicesByPoint['김녕']!;
      expect(kimnyeong, hasLength(4));

      final first = kimnyeong.first;
      expect(first.date, DateTime(2026, 8, 1));
      expect(first.pointName, '김녕');
      expect(first.tidePhase, '대조기');
      // 같은 날짜 안에서는 오전이 먼저 온다.
      expect(first.timeSlot, '오전');

      final morningGrades = kimnyeong
          .where((i) => i.date == DateTime(2026, 8, 1) && i.timeSlot == '오전')
          .map((i) => '${i.species}:${i.grade.label}')
          .toList();
      expect(morningGrades, containsAll(['감성돔:좋음', '우럭:보통']));
    });

    test('가장 가까운 포인트를 고른다', () {
      final file = parseFishingIndexFile(sampleFile());

      expect(file.forecastFor(_jeju).indices.first.pointName, '김녕');
      expect(file.forecastFor(_far).indices.first.pointName, '가거도');
    });
  });

  group('GithubFishingRepository', () {
    test('지역을 여러 번 바꿔도 파일은 한 번만 받는다', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = CacheStore(await SharedPreferences.getInstance());
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return _jsonResponse(sampleFile());
      });
      final direct = _NeverRepository();
      final repo = GithubFishingRepository(
        direct: direct,
        cache: cache,
        client: client,
        url: 'https://example.test/fishing_index.json.gz',
      );

      expect((await repo.fetchForecast(_jeju)).indices, isNotEmpty);
      expect((await repo.fetchForecast(_far)).indices, isNotEmpty);
      expect((await repo.fetchForecast(_jeju)).indices, isNotEmpty);

      // 예전엔 지역마다 전국 데이터를 다시 받아 매번 몇 초씩 걸렸다.
      expect(calls, 1);
      expect(direct.calls, 0);
    });

    test('gzip으로 내려와도 푼다', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = CacheStore(await SharedPreferences.getInstance());
      final client = MockClient(
        (_) async =>
            http.Response.bytes(gzip.encode(utf8.encode(sampleFile())), 200),
      );
      final repo = GithubFishingRepository(
        direct: _NeverRepository(),
        cache: cache,
        client: client,
        url: 'https://example.test/fishing_index.json.gz',
      );

      final forecast = await repo.fetchForecast(_jeju);
      expect(forecast.indices.first.pointName, '김녕');
    });

    test('파일을 못 받으면 직접 호출로 폴백한다', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = CacheStore(await SharedPreferences.getInstance());
      final client = MockClient((_) async => http.Response('nope', 404));
      final direct = _StubRepository();
      final repo = GithubFishingRepository(
        direct: direct,
        cache: cache,
        client: client,
        url: 'https://example.test/fishing_index.json.gz',
      );

      await repo.fetchForecast(_jeju);
      expect(direct.calls, 1);
    });

    test('앱을 껐다 켜도 디스크 캐시로 즉시 뜬다', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = CacheStore(await SharedPreferences.getInstance());
      const url = 'https://example.test/fishing_index.json.gz';

      var calls = 0;
      await GithubFishingRepository(
        direct: _NeverRepository(),
        cache: cache,
        client: MockClient((_) async {
          calls++;
          return _jsonResponse(sampleFile());
        }),
        url: url,
      ).fetchForecast(_jeju);
      expect(calls, 1);

      // 저장은 일부러 await하지 않으므로(화면을 먼저 그리려고) 여기서 기다린다.
      for (var i = 0; i < 200 && cache.readString(_todayKey()) == null; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(cache.readString(_todayKey()), isNotNull);

      GithubFishingRepository.clearMemoryCache();
      final offline = MockClient(
        (_) async => throw http.ClientException('오프라인'),
      );
      final forecast = await GithubFishingRepository(
        direct: _NeverRepository(),
        cache: cache,
        client: offline,
        url: url,
      ).fetchForecast(_jeju);

      expect(forecast.indices.first.pointName, '김녕');
    });
  });

  group('어종 목록', () {
    test('제철 어종은 모두 후보 목록 안에 있다', () {
      // API가 주지 않는 어종을 기본값으로 두면 지수가 영영 빈칸으로 남는다.
      for (final month in List.generate(12, (i) => i + 1)) {
        for (final s in seasonalSpecies(month)) {
          expect(
            fishingSpeciesCatalog,
            contains(s),
            reason: '$month월 제철 어종 "$s"가 후보 목록에 없다',
          );
        }
      }
      for (final s in defaultFishingSpecies) {
        expect(fishingSpeciesCatalog, contains(s));
      }
      for (final region in ['서해', '남해', '동해', '기타']) {
        for (final s in preferredSpeciesForRegion(region)) {
          expect(fishingSpeciesCatalog, contains(s), reason: '$region: $s');
        }
      }
    });
  });
}

/// charset을 명시한다 — `http.Response(String, ...)`는 charset 헤더가 없으면
/// latin1로 인코딩해서 한글이 깨진다(실제 서버 응답은 UTF-8을 명시한다).
http.Response _jsonResponse(String body) => http.Response(
  body,
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

String _todayKey() {
  final n = DateTime.now();
  return 'fishing_file_${n.year}'
      '${n.month.toString().padLeft(2, '0')}'
      '${n.day.toString().padLeft(2, '0')}';
}
