import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../../core/config/env.dart';
import '../../../../core/network/data_go_kr.dart';
import '../../../../core/storage/cache_store.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/fishing_index.dart';
import 'fishing_repository.dart';

/// 공공데이터포털 「해양수산부 국립해양조사원_바다낚시지수 조회」 리포지토리.
///
/// End Point: https://apis.data.go.kr/1192136/fcstFishingv2  (활용신청 승인됨)
/// 오퍼레이션: GetFcstFishingApiServicev2  (포털 미리보기 URL 실측)
///
/// 실측(2026-07) 확정 필드:
///   seafsPstnNm  포인트명 / lat, lot 좌표
///   predcYmd     예보일 "yyyy-MM-dd" / predcNoonSeCd  오전·오후
///   seafsTgfshNm 어종 / totalIndex  지수 라벨(매우나쁨~매우좋음)
///   tdlvHrCn     물때 구분(대조기 등) / min·maxWvhgt 파고 / min·maxWtem 수온
///
/// 하루치 전체 포인트를 받아 선택 지역과 가장 가까운 포인트의 지수를 돌려준다.
class DataGoKrFishingRepository implements FishingRepository {
  DataGoKrFishingRepository({
    http.Client? client,
    String? serviceKey,
    this.cache,
  }) : _client = client ?? http.Client(),
       _serviceKey = serviceKey ?? Env.dataGoKrApiKey;

  final http.Client _client;
  final String _serviceKey;

  /// 하루치 전국 원본을 담아 둘 로컬 캐시. 없으면 메모리 캐시만 쓴다.
  final CacheStore? cache;

  static const _host = 'apis.data.go.kr';
  static const _basePath = '/1192136/fcstFishingv2';

  /// 한 쪽에 받을 건수. **이 API의 실측 상한은 300이다.**
  /// 그보다 크게 넣으면 HTTP 200에 `resultCode: 10
  /// INVALID_REQUEST_PARAMETER_ERROR`만 담긴 76B가 돌아온다 — 예전에 3000으로
  /// 요청하다가 늘 빈 응답을 받고 조용히 합성 데이터로 폴백하던 원인이었다.
  /// 이 값을 올릴 땐 `tool/probe_fishing.py`로 실제 응답을 먼저 확인한다.
  static const _pageRows = 300;

  /// 전국 하루치는 현재 1,750건(6쪽)이다. 안전장치로 넉넉히 잡는다.
  static const _maxPages = 20;

  /// 응답이 없을 때 무한정 기다리지 않는다 — 예전엔 타임아웃이 없어서
  /// API가 느리면 화면이 그만큼 로딩에 머물렀다.
  static const _timeout = Duration(seconds: 10);

  /// 날짜별 디스크 캐시 키. **지역이 아니라 날짜 단위**여야 한다 —
  /// 받아 오는 건 전국 원본이라 지역별로 저장하면 새 지역마다 같은 데이터를
  /// 다시 받게 된다(실제로 지역을 바꿀 때마다 3~5초씩 걸리던 원인).
  static const _dayCacheKey = 'fishing_day_';

  /// 하루치 **전국** 응답(약 1,750건)은 어느 지역을 고르든 완전히 같으므로,
  /// 날짜별로 한 번만 받아 재사용한다 — 새 지역을 골라도 네트워크 재요청 없이
  /// 가까운 포인트 필터만 다시 해서 즉시 뜬다. (같은 원본을 그대로 쓰는
  /// 것이라 실시간 값이 틀어지지 않는다.)
  static final Map<String, Future<List<Map<String, dynamic>>>> _dayItems = {};

  @visibleForTesting
  static void clearMemoryCache() => _dayItems.clear();

  Future<List<Map<String, dynamic>>> _itemsFor(String ymd) =>
      _dayItems.putIfAbsent(ymd, () => _loadDay(ymd));

  Future<List<Map<String, dynamic>>> _loadDay(String ymd) async {
    final key = '$_dayCacheKey$ymd';

    // 같은 날짜면 원본이 같으므로 디스크 캐시를 먼저 쓴다. 앱을 껐다 켜도
    // 첫 조회가 즉시 뜬다(예전엔 메모리 캐시뿐이라 재시작마다 다시 받았다).
    final cached = cache?.readString(key);
    if (cached != null) {
      final items = await _decode(cached);
      if (items.isNotEmpty) return items;
    }

    try {
      final items = <Map<String, dynamic>>[];
      for (var page = 1; page <= _maxPages; page++) {
        final uri = Uri.https(_host, '$_basePath/GetFcstFishingApiServicev2', {
          'serviceKey': _serviceKey,
          'type': 'json',
          'reqDate': ymd,
          'gubun': '갯바위',
          'pageNo': '$page',
          'numOfRows': '$_pageRows',
        });
        final res = await _client.get(uri).timeout(_timeout);
        if (res.statusCode != 200) {
          throw http.ClientException('바다낚시지수 응답 오류 ${res.statusCode}', uri);
        }
        final got = await _parse(res.body);
        items.addAll(got);
        if (got.length < _pageRows) break; // 마지막 쪽
      }
      if (items.isEmpty) {
        throw const FormatException('바다낚시지수 응답에 데이터가 없음');
      }
      // 저장을 기다리지 않는다 — 디스크 쓰기가 끝나야 화면에 뜨던 지연 제거.
      // 새 날짜를 받았으면 지난 날짜 캐시(전국 원본·지역별 결과)도 함께
      // 정리한다. 오늘 날짜로 끝나는 키는 남기므로 오프라인 폴백은 유지된다.
      // 하루에 한 번만 도는 경로라 비용이 사실상 없다.
      final store = cache;
      if (store != null) {
        unawaited(
          store
              .writeString(key, jsonEncode(items))
              .then(
                (_) =>
                    store.pruneStale('fishing_', keep: (k) => k.endsWith(ymd)),
              )
              .catchError((_) {}),
        );
      }
      return items;
    } catch (_) {
      // 실패한 날짜는 메모리에 남기지 않아 다음 조회에서 다시 시도한다.
      _dayItems.remove(ymd);
      rethrow;
    }
  }

  /// 응답 본문(수 MB)을 파싱한다. 큰 본문은 **백그라운드 아이솔레이트**에서
  /// 처리해 파싱 동안 화면이 멈추지 않게 한다. 작은 본문(테스트·빈 응답)은
  /// 아이솔레이트를 띄우는 비용이 더 커서 그냥 여기서 처리한다.
  static Future<List<Map<String, dynamic>>> _parse(String body) =>
      body.length > _isolateThreshold
      ? compute(slimFishingItems, body)
      : Future.value(slimFishingItems(body));

  static Future<List<Map<String, dynamic>>> _decode(String raw) =>
      raw.length > _isolateThreshold
      ? compute(_decodeItems, raw)
      : Future.value(_decodeItems(raw));

  static const _isolateThreshold = 64 * 1024;

  @override
  Future<FishingForecast> fetchForecast(SeaLocation location) async {
    final today = DateTime.now();
    final ymd =
        '${today.year}'
        '${today.month.toString().padLeft(2, '0')}'
        '${today.day.toString().padLeft(2, '0')}';
    final items = await _itemsFor(ymd);

    final nearest = _nearestPointName(items, location);
    final indices =
        items
            .where((i) => i['seafsPstnNm'] == nearest)
            .map(mapFishingItem)
            .toList()
          ..sort((a, b) {
            final byDate = a.date.compareTo(b.date);
            if (byDate != 0) return byDate;
            return a.timeSlot.compareTo(b.timeSlot); // 오전 < 오후 (가나다순)
          });

    return FishingForecast(locationId: location.id, indices: indices);
  }

  /// 선택 지역과 가장 가까운 낚시 포인트 이름 (단순 위경도 거리 비교).
  String _nearestPointName(
    List<Map<String, dynamic>> items,
    SeaLocation location,
  ) {
    String? best;
    var bestD2 = double.infinity;
    final seen = <String>{};
    for (final item in items) {
      final name = item['seafsPstnNm']?.toString();
      if (name == null || !seen.add(name)) continue;
      final lat = (item['lat'] as num?)?.toDouble();
      final lot = (item['lot'] as num?)?.toDouble();
      if (lat == null || lot == null) continue;
      final dLat = lat - location.latitude;
      final dLot = lot - location.longitude;
      final d2 = dLat * dLat + dLot * dLot;
      if (d2 < bestD2) {
        bestD2 = d2;
        best = name;
      }
    }
    if (best == null) {
      throw const FormatException('낚시 포인트 좌표를 찾을 수 없음');
    }
    return best;
  }
}

/// 응답 본문을 파싱해 **실제로 쓰는 필드만** 남긴다.
///
/// 전국 하루치는 항목마다 수십 개 필드가 붙어 오는데 앱이 읽는 건 아래 12개
/// 뿐이다. 여기서 걸러 두면 캐시에 저장할 양이 크게 줄어든다.
/// [compute]로 넘기려고 최상위 함수로 둔다(클로저는 아이솔레이트로 못 보낸다).
List<Map<String, dynamic>> slimFishingItems(String body) {
  const keep = {
    'seafsPstnNm', 'lat', 'lot', // 포인트 이름·좌표(가장 가까운 곳 찾기)
    'predcYmd', 'predcNoonSeCd', // 예보일·오전/오후
    'totalIndex', 'seafsTgfshNm', // 지수 등급·어종
    'tdlvHrCn', // 물때 구분
    'minWvhgt', 'maxWvhgt', 'minWtem', 'maxWtem', // 파고·수온
  };
  return [
    for (final item in parseDataGoKrItems(body))
      {
        for (final entry in item.entries)
          if (keep.contains(entry.key)) entry.key: entry.value,
      },
  ];
}

List<Map<String, dynamic>> _decodeItems(String raw) => [
  for (final e in jsonDecode(raw) as List) (e as Map).cast<String, dynamic>(),
];

/// 낚시지수 응답 item 하나를 [FishingIndex]로 변환한다.
FishingIndex mapFishingItem(Map<String, dynamic> item) {
  double? avg(String minKey, String maxKey) {
    final min = (item[minKey] as num?)?.toDouble();
    final max = (item[maxKey] as num?)?.toDouble();
    if (min == null) return max;
    if (max == null) return min;
    return (min + max) / 2;
  }

  final dateRaw = item['predcYmd']?.toString();
  final indexRaw = item['totalIndex']?.toString();
  if (dateRaw == null || indexRaw == null) {
    throw FormatException('알 수 없는 낚시지수 필드 구성: ${item.keys.join(', ')}');
  }

  return FishingIndex(
    date: DateTime.parse(dateRaw),
    timeSlot: item['predcNoonSeCd']?.toString() ?? '',
    grade: FishingGrade.fromLabel(indexRaw),
    species: item['seafsTgfshNm']?.toString(),
    pointName: item['seafsPstnNm']?.toString(),
    tidePhase: item['tdlvHrCn']?.toString(),
    waveHeightM: avg('minWvhgt', 'maxWvhgt'),
    waterTempC: avg('minWtem', 'maxWtem'),
  );
}
