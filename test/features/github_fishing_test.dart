import 'dart:convert';
import 'dart:io' show gzip;

import 'package:bada_mobile/core/storage/cache_store.dart';
import 'package:bada_mobile/features/fishing/data/models/fishing_index.dart';
import 'package:bada_mobile/features/fishing/data/models/jigging_estimate.dart';
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
///
/// [from]을 주면 그날과 다음날 지수로 만든다. **리포지토리 경로를 타는
/// 테스트는 반드시 오늘 날짜로 만들어야 한다** — 오늘자가 없는 파일은
/// "수집이 멈춘 상태"로 보고 직접 호출로 폴백하기 때문이다.
String sampleFile({DateTime? from, DateTime? generatedAt}) {
  final day0 = from ?? DateTime(2026, 8, 1);
  final day1 = day0.add(const Duration(days: 1));
  String ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  // `generated`도 같이 움직여야 한다 — 앱은 "오늘이 들어 있는가"만이 아니라
  // **언제 만든 파일인가**로도 판단한다.
  final made =
      generatedAt?.toUtc() ?? DateTime.utc(day0.year, day0.month, day0.day, 9);
  return _sampleWithDates(ymd(day0), ymd(day1), made.toIso8601String());
}

/// 오늘자 지수가 들어 있는 표본 파일(서버 수집이 정상인 상태).
String freshSampleFile() => sampleFile(from: DateTime.now());

String _sampleWithDates(String d0, String d1, String made) => jsonEncode({
  'fmt': 1,
  'generated': made,
  'points': [
    {'n': '가거도', 'la': 34.073, 'lo': 125.088},
    {'n': '김녕', 'la': 33.558, 'lo': 126.758},
    // 총 지수만 있고 어종이 '-'인 포인트(실제 파일의 49곳 중 15곳이 이렇다).
    {'n': '제주항 북측', 'la': 33.52, 'lo': 126.53},
  ],
  'dates': [d0, d1],
  'species': ['감성돔', '우럭', '-', '기타어종'],
  'tides': ['대조기'],
  'slots': ['오전', '오후'],
  // [포인트, 날짜, 오전/오후, 어종, 등급, 파고m, 수온C, 물때]
  'rows': [
    [0, 0, 0, 0, '나쁨', 1.2, 24.0, 0],
    [1, 0, 0, 0, '좋음', 0.9, 25.3, 0],
    [1, 0, 1, 0, '매우좋음', 0.8, 25.5, 0],
    [1, 0, 0, 1, '보통', 0.9, 25.3, 0],
    [1, 1, 0, 0, '매우나쁨', 1.5, 25.1, 0],
    [2, 0, 0, 2, '좋음', 0.5, 26.0, 0],
    [2, 0, 1, 2, '보통', 0.5, 26.0, 0],
    // API가 함께 주는 묶음 값 — 선택 목록에는 나오면 안 된다.
    [1, 0, 0, 3, '보통', 0.9, 25.3, 0],
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

      expect(file.points, hasLength(3));
      expect(file.generated, DateTime.utc(2026, 8, 1, 9));

      final kimnyeong = file.indicesByPoint['김녕']!;
      expect(kimnyeong, hasLength(5)); // 어종 4건 + 묶음(기타어종) 1건

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

    test('어종이 없는 포인트는 더 가까워도 건너뛴다', () {
      final file = parseFishingIndexFile(sampleFile());
      // 제주시내는 '제주항 북측'(어종 '-'만 있음)이 훨씬 가깝지만, 그곳을
      // 고르면 화면에 "이 날짜의 낚시지수가 없습니다"만 뜬다.
      const jejuCity = SeaLocation(
        id: 'jeju_city',
        name: '제주시',
        region: '제주',
        latitude: 33.51,
        longitude: 126.52,
      );
      final picked = file.forecastFor(jejuCity);
      expect(picked.indices.first.pointName, '김녕');
      expect(
        picked.indices.any((i) => i.species != null && i.species != '-'),
        isTrue,
      );
    });
  });

  group('GithubFishingRepository', () {
    test('지역을 여러 번 바꿔도 파일은 한 번만 받는다', () async {
      SharedPreferences.setMockInitialValues({});
      final cache = CacheStore(await SharedPreferences.getInstance());
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return _jsonResponse(freshSampleFile());
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
        (_) async => http.Response.bytes(
          gzip.encode(utf8.encode(freshSampleFile())),
          200,
        ),
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

    test('오늘자가 없는 낡은 파일이면 직접 호출로 폴백한다', () async {
      // 서버 수집이 멈추면 릴리스에는 며칠 전 파일이 그대로 남는다
      // (2026-08, data.go.kr 타임아웃으로 사흘 연속 실패). 그걸 그냥 쓰면
      // 화면에 "이 날짜의 낚시지수가 없습니다"만 뜬다.
      SharedPreferences.setMockInitialValues({});
      final cache = CacheStore(await SharedPreferences.getInstance());
      final stale = sampleFile(
        from: DateTime.now().subtract(const Duration(days: 3)),
      );
      final direct = _StubRepository();
      final repo = GithubFishingRepository(
        direct: direct,
        cache: cache,
        client: MockClient((_) async => _jsonResponse(stale)),
        url: 'https://example.test/fishing_index.json.gz',
      );

      await repo.fetchForecast(_jeju);
      expect(direct.calls, 1, reason: '낡은 파일을 붙들고 있으면 안 된다');
    });

    test('오늘이 들어 있어도 만든 지 오래된 파일이면 직접 호출을 먼저 쓴다', () async {
      // 이 API는 며칠 앞까지 주므로, 수집이 멈춰도 이틀쯤은 "오늘이 들어
      // 있는" 낡은 파일이 남는다. 그동안 예보는 갱신되는데 앱만 이틀 전
      // 판단을 계속 보여 주게 된다(2026-08-06에 실제로 이 상태였다).
      SharedPreferences.setMockInitialValues({});
      final cache = CacheStore(await SharedPreferences.getInstance());
      // 이틀 전에 만들었지만 날짜는 오늘·내일까지 담고 있는 파일.
      final stale = sampleFile(
        from: DateTime.now(),
        generatedAt: DateTime.now().subtract(const Duration(days: 2)),
      );

      final direct = _StubRepository();
      await GithubFishingRepository(
        direct: direct,
        cache: cache,
        client: MockClient((_) async => _jsonResponse(stale)),
        url: 'https://example.test/fishing_index.json.gz',
      ).fetchForecast(_jeju);

      expect(direct.calls, 1, reason: '이틀 전 판단을 그대로 보여 주면 안 된다');
    });

    test('직접 호출까지 실패하면 낡은 파일이라도 쓴다(합성보다 낫다)', () async {
      // 여기서 그냥 던지면 체인이 목(합성 데이터)까지 내려간다. 이틀 전
      // 것이어도 실제 관측에 기반한 오늘 값이 합성보다는 낫다.
      SharedPreferences.setMockInitialValues({});
      final cache = CacheStore(await SharedPreferences.getInstance());
      final stale = sampleFile(
        from: DateTime.now(),
        generatedAt: DateTime.now().subtract(const Duration(days: 2)),
      );

      final direct = _NeverRepository(); // 직접 호출은 늘 실패
      final forecast = await GithubFishingRepository(
        direct: direct,
        cache: cache,
        client: MockClient((_) async => _jsonResponse(stale)),
        url: 'https://example.test/fishing_index.json.gz',
      ).fetchForecast(_jeju);

      expect(direct.calls, 1);
      expect(forecast.indices, isNotEmpty, reason: '합성으로 내려가지 말고 이 파일을 써야 한다');
    });

    test('낡은 파일은 디스크 캐시에 있어도 쓰지 않는다', () async {
      // 오늘 아침에 받아 둔 것이 그 시점엔 최신이었어도, 릴리스가 며칠 전
      // 것이었다면 캐시에도 낡은 내용이 들어간다.
      SharedPreferences.setMockInitialValues({});
      final cache = CacheStore(await SharedPreferences.getInstance());
      final stale = sampleFile(
        from: DateTime.now().subtract(const Duration(days: 3)),
      );
      await cache.writeString(_todayKey(), stale);

      final direct = _StubRepository();
      await GithubFishingRepository(
        direct: direct,
        cache: cache,
        client: MockClient((_) async => throw http.ClientException('오프라인')),
        url: 'https://example.test/fishing_index.json.gz',
      ).fetchForecast(_jeju);

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
          return _jsonResponse(freshSampleFile());
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

  group('availableSpecies', () {
    test('묶음(기타어종)·빈 값(-)은 선택 목록에서 뺀다', () {
      final file = parseFishingIndexFile(sampleFile());
      final available = file.forecastFor(_jeju).availableSpecies;

      expect(available, contains('감성돔'));
      expect(available, contains('우럭'));
      // 특정 어종이 아니라 사용자가 고를 값으로 의미가 없다.
      expect(available, isNot(contains('기타어종')));
      expect(available, isNot(contains('-')));
    });

    test('후보 목록은 API가 주는 어종만 담는다', () {
      // 광어·문어·쭈꾸미·갑오징어는 이 API에 없다(gubun을 바꿔도 없다).
      // 목록에 넣으면 고를 수는 있어도 지수가 영영 빈칸이 된다.
      for (final absent in ['광어', '문어', '쭈꾸미', '갑오징어', '삼치', '볼락']) {
        expect(fishingSpeciesCatalog, isNot(contains(absent)));
      }
      expect(fishingSpeciesCatalog, isNot(contains('기타어종')));
      expect(fishingSpeciesCatalog, hasLength(6));
    });
  });

  group('어종 목록', () {
    test('제철 어종은 모두 후보 목록 안에 있다', () {
      // 관측·추정 어느 쪽에도 없는 어종을 기본값으로 두면 빈칸이 된다.
      final known = {...fishingSpeciesCatalog, ...estimatedSpeciesCatalog};
      for (final month in List.generate(12, (i) => i + 1)) {
        for (final s in seasonalSpecies(month)) {
          expect(
            known,
            contains(s),
            reason: '$month월 제철 어종 "$s"가 관측·추정 목록 어디에도 없다',
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
