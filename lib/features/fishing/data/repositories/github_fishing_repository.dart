import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/env.dart';
import '../../../../core/storage/cache_store.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/fishing_index.dart';
import 'fishing_repository.dart';

/// 서버(GitHub Actions 크론)가 미리 모아 롤링 릴리스에 올린 낚시지수 파일을
/// 내려받아 쓰는 리포지토리. 바람장([GithubWindFieldRepository])과 같은 구조다.
///
/// **왜 이렇게 하나** — data.go.kr의 낚시지수 API는 `numOfRows` 상한이 300이라
/// 전국 1,750건을 받으려면 6쪽을 나눠 받아야 하고 6초쯤 걸린다(실측). 게다가
/// 앱이 받는 건 그중 가장 가까운 포인트 1곳뿐이다. 하루 한 번 갱신되는
/// 예보이므로 서버가 한 번 모아 두면 앱은 약 20KB 파일 하나로 끝난다.
///
/// 파일은 **날짜별로 디스크에 캐시**한다. 같은 날 다시 열거나 지역을 바꿔도
/// 네트워크를 타지 않는다. 파일을 못 받으면 [direct](data.go.kr 직접 호출)로
/// 폴백한다.
class GithubFishingRepository implements FishingRepository {
  GithubFishingRepository({
    required this.direct,
    required this.cache,
    http.Client? client,
    String? url,
  }) : _client = client ?? http.Client(),
       _url = url ?? Env.fishingDataUrl;

  final FishingRepository direct;
  final CacheStore cache;
  final http.Client _client;
  final String _url;

  static const _timeout = Duration(seconds: 12);
  static const _cacheKey = 'fishing_file_';

  /// 세션 안에서 같은 날짜 파일을 두 번 받지 않게 하는 메모리 캐시.
  /// 지역을 바꿀 때마다 다시 파싱하지 않으려고 결과 자체를 들고 있는다.
  static final Map<String, Future<FishingIndexFile>> _memo = {};

  @visibleForTesting
  static void clearMemoryCache() => _memo.clear();

  @override
  Future<FishingForecast> fetchForecast(SeaLocation location) async {
    if (_url.isEmpty) return direct.fetchForecast(location);
    final ymd = _todayYmd();

    FishingIndexFile? file;
    try {
      file = await _memo.putIfAbsent(ymd, () => _load(ymd));
    } catch (_) {
      _memo.remove(ymd);
    }

    if (file != null && _isCurrent(file)) return file.forecastFor(location);

    // 파일이 없거나 낡았다 — 느리더라도 직접 받아 온다.
    try {
      return await direct.fetchForecast(location);
    } catch (_) {
      // 직접 호출도 실패. **낡았어도 오늘 값이 있으면 그게 합성 데이터보다
      // 낫다** — 여기서 그냥 던지면 체인이 목(합성)까지 내려간다.
      if (file != null && file.covers(DateTime.now())) {
        return file.forecastFor(location);
      }
      rethrow;
    }
  }

  Future<FishingIndexFile> _load(String ymd) async {
    final key = '$_cacheKey$ymd';

    // 같은 날짜면 내용이 같으므로 디스크 캐시를 먼저 쓴다(앱 재시작 후 즉시).
    final cached = cache.readString(key);
    if (cached != null) {
      try {
        return await compute(parseFishingIndexFile, cached);
      } catch (_) {
        // 캐시가 깨졌거나 낡았으면 새로 받는다.
      }
    }

    final res = await _client.get(Uri.parse(_url)).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('낚시지수 파일 응답 오류 ${res.statusCode}');
    }
    var bytes = res.bodyBytes;
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      bytes = Uint8List.fromList(gzip.decode(bytes));
    }
    final json = utf8.decode(bytes);
    final file = await compute(parseFishingIndexFile, json);

    // 저장은 기다리지 않는다. 지난 날짜 캐시는 함께 정리한다.
    unawaited(
      cache
          .writeString(key, json)
          .then(
            (_) => cache.pruneStale(_cacheKey, keep: (k) => k.endsWith(ymd)),
          )
          .catchError((_) {}),
    );
    return file;
  }

  /// 이 파일만으로 충분한가 — 아니면 직접 호출을 먼저 시도할 것인가.
  ///
  /// 두 가지를 본다.
  /// - **오늘 날짜 지수가 들어 있는가.** 없으면 화면에 "이 날짜의 낚시지수가
  ///   없습니다"만 뜬다.
  /// - **언제 만들어진 파일인가.** 이 API는 며칠 앞까지 주므로, 수집이 멈춰도
  ///   이틀쯤은 "오늘이 들어 있는" 낡은 파일이 남는다(2026-08 실제로 겪음).
  ///   그동안 예보는 갱신되는데 앱은 이틀 전 판단을 계속 보여 준다.
  ///
  /// 여기서 false가 나와도 파일을 버리지는 않는다 — 직접 호출까지 실패하면
  /// [fetchForecast]가 이 파일로 되돌아온다(합성 데이터보다는 낫다).
  bool _isCurrent(FishingIndexFile file) {
    if (!file.covers(DateTime.now())) return false;
    final at = file.generated;
    // 만든 시각을 모르는 파일(옛 형식)은 새것이라고 볼 근거가 없다.
    if (at == null) return false;
    return DateTime.now().toUtc().difference(at.toUtc()) < _staleAfter;
  }

  /// 하루 한 번 갱신되므로 다음 수집 직전이면 24시간이 조금 넘는다.
  /// 그보다 더 오래됐으면 수집이 멈춘 것으로 본다.
  static const _staleAfter = Duration(hours: 30);

  static String _todayYmd() {
    final n = DateTime.now();
    return '${n.year}'
        '${n.month.toString().padLeft(2, '0')}'
        '${n.day.toString().padLeft(2, '0')}';
  }
}

/// [fetch_fishing.py]가 만든 파일을 앱이 쓰는 형태로 담은 것.
///
/// 같은 문자열(포인트명·어종·물때)이 수백 번 반복되므로 파일은 표로 빼고
/// 행에는 번호만 담는다. 이 클래스가 그 번호를 되돌린다.
@immutable
class FishingIndexFile {
  const FishingIndexFile({
    required this.points,
    required this.indicesByPoint,
    required this.generated,
  });

  /// 포인트 이름 → 좌표.
  final List<FishingPoint> points;

  /// 포인트 이름 → 그 포인트의 지수 목록(날짜·오전/오후 순 정렬).
  final Map<String, List<FishingIndex>> indicesByPoint;

  final DateTime? generated;

  /// 파일이 [day]자 지수를 담고 있는가.
  ///
  /// **서버 수집이 멈추면 릴리스에는 며칠 전 파일이 그대로 남아 있고**,
  /// 앱은 그걸 받아 오늘 칸이 빈 화면("이 날짜의 낚시지수가 없습니다")을
  /// 보여준다(2026-08, data.go.kr 타임아웃으로 사흘 연속 수집 실패 때 발생).
  /// [GithubFishingRepository]가 이 값을 보고 낡은 파일이면 직접 호출로
  /// 넘어간다.
  bool covers(DateTime day) {
    for (final list in indicesByPoint.values) {
      for (final i in list) {
        if (i.date.year == day.year &&
            i.date.month == day.month &&
            i.date.day == day.day) {
          return true;
        }
      }
    }
    return false;
  }

  /// [location]에서 가장 가까운 포인트의 지수를 돌려준다.
  ///
  /// **어종별 지수가 있는 포인트만 후보로 본다.** 전국 49곳 중 15곳은 총 지수만
  /// 있고 어종이 `-`로 와서(2026-08 실측), 그런 곳이 걸리면 화면에 "이 날짜의
  /// 낚시지수가 없습니다"만 뜬다. 조금 더 멀어도 값이 있는 포인트를 고른다.
  FishingForecast forecastFor(SeaLocation location) {
    if (points.isEmpty) {
      throw const FormatException('낚시지수 파일에 포인트가 없음');
    }
    final usable = [
      for (final p in points)
        if (_hasSpecies(p.name)) p,
    ];
    final candidates = usable.isNotEmpty ? usable : points;

    var best = candidates.first;
    var bestD2 = double.infinity;
    for (final p in candidates) {
      final dLat = p.latitude - location.latitude;
      final dLon = p.longitude - location.longitude;
      final d2 = dLat * dLat + dLon * dLon;
      if (d2 < bestD2) {
        bestD2 = d2;
        best = p;
      }
    }
    return FishingForecast(
      locationId: location.id,
      indices: indicesByPoint[best.name] ?? const [],
    );
  }

  bool _hasSpecies(String point) => (indicesByPoint[point] ?? const []).any(
    (i) => i.species != null && !nonSpeciesLabels.contains(i.species),
  );
}

@immutable
class FishingPoint {
  const FishingPoint({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final double latitude;
  final double longitude;
}

/// 파일 JSON 문자열을 [FishingIndexFile]로 파싱한다.
/// [compute]로 넘기려고 최상위 함수이고 인자·반환이 모두 전달 가능해야 한다.
FishingIndexFile parseFishingIndexFile(String source) {
  final json = jsonDecode(source) as Map<String, dynamic>;

  List<String> strings(String key) => [
    for (final e in (json[key] as List? ?? const [])) e.toString(),
  ];

  final dates = strings('dates');
  final species = strings('species');
  final tides = strings('tides');
  final slots = strings('slots');

  final points = [
    for (final p in (json['points'] as List? ?? const []))
      FishingPoint(
        name: (p as Map)['n'].toString(),
        latitude: (p['la'] as num).toDouble(),
        longitude: (p['lo'] as num).toDouble(),
      ),
  ];

  String? at(List<String> table, Object? i) {
    final n = (i as num?)?.toInt();
    if (n == null || n < 0 || n >= table.length) return null;
    return table[n];
  }

  final pointNames = [for (final p in points) p.name];
  final byPoint = <String, List<FishingIndex>>{};
  for (final raw in (json['rows'] as List? ?? const [])) {
    final row = raw as List;
    final point = at(pointNames, row[0]);
    final date = at(dates, row[1]);
    if (point == null || date == null) continue;
    (byPoint[point] ??= []).add(
      FishingIndex(
        date: DateTime.parse(date),
        timeSlot: at(slots, row[2]) ?? '',
        grade: FishingGrade.fromLabel(row[4].toString()),
        species: at(species, row[3]),
        pointName: point,
        tidePhase: at(tides, row[7]),
        waveHeightM: (row[5] as num?)?.toDouble(),
        waterTempC: (row[6] as num?)?.toDouble(),
      ),
    );
  }

  for (final list in byPoint.values) {
    list.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.timeSlot.compareTo(b.timeSlot);
    });
  }

  return FishingIndexFile(
    points: points,
    indicesByPoint: byPoint,
    generated: DateTime.tryParse(json['generated']?.toString() ?? ''),
  );
}
