import 'package:http/http.dart' as http;

import '../../../../core/config/env.dart';
import '../../../../core/network/data_go_kr.dart';
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
  DataGoKrFishingRepository({http.Client? client, String? serviceKey})
    : _client = client ?? http.Client(),
      _serviceKey = serviceKey ?? Env.dataGoKrApiKey;

  final http.Client _client;
  final String _serviceKey;

  static const _host = 'apis.data.go.kr';
  static const _basePath = '/1192136/fcstFishingv2';

  /// 하루치 **전국** 응답(약 1,750건)은 어느 지역을 고르든 완전히 같으므로,
  /// 세션 안에서는 날짜별로 한 번만 받아 재사용한다 — 새 지역을 골라도
  /// 네트워크 재요청 없이 가까운 포인트 필터만 다시 해서 즉시 뜬다.
  /// (같은 원본을 그대로 쓰는 것이라 실시간 값이 틀어지지 않는다.
  /// 실패한 요청은 캐시하지 않아 다음 조회에서 재시도한다.)
  static final Map<String, Future<List<Map<String, dynamic>>>> _dayItems = {};

  Future<List<Map<String, dynamic>>> _itemsFor(String ymd) {
    return _dayItems.putIfAbsent(ymd, () async {
      try {
        final uri = Uri.https(_host, '$_basePath/GetFcstFishingApiServicev2', {
          'serviceKey': _serviceKey,
          'type': 'json',
          'reqDate': ymd,
          'gubun': '갯바위',
          'pageNo': '1',
          'numOfRows': '3000', // 전체 포인트×어종×오전/오후 (하루 약 1,750건)
        });
        final res = await _client.get(uri);
        if (res.statusCode != 200) {
          throw http.ClientException('바다낚시지수 응답 오류 ${res.statusCode}', uri);
        }
        final items = parseDataGoKrItems(res.body);
        if (items.isEmpty) {
          throw const FormatException('바다낚시지수 응답에 데이터가 없음');
        }
        return items;
      } catch (_) {
        _dayItems.remove(ymd);
        rethrow;
      }
    });
  }

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
