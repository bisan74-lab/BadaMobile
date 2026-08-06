import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../../../core/config/env.dart';
import '../../../../core/network/data_go_kr.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/tide_data.dart';
import 'tide_repository.dart';

/// 공공데이터포털 「해양수산부 국립해양조사원_조석예보(고,저조)」 리포지토리.
///
/// End Point: https://apis.data.go.kr/1192136/tideFcstHghLw  (활용신청 승인됨)
/// 인증: data.go.kr 일반 인증키 (`Env.dataGoKrApiKey`, --dart-define 주입)
///
/// 이 API는 하루 3~4회의 고조/저조 극값만 제공한다. 조위 곡선 차트용
/// 시간별 조위는 인접 극값 사이를 코사인 보간해 생성한다(조석 앱 표준 기법).
/// 전날/다음날 극값까지 함께 조회해 자정 부근 곡선이 매끄럽게 이어지게 한다.
///
/// 응답 필드명은 KHOA 계열 API의 알려진 명명 후보(camel/snake)를 허용하며,
/// 매핑 실패 시 예외를 던져 폴백(합성 데이터)으로 넘어간다.
class DataGoKrTideRepository implements TideRepository {
  DataGoKrTideRepository({http.Client? client, String? serviceKey})
    : _client = client ?? http.Client(),
      _serviceKey = serviceKey ?? Env.dataGoKrApiKey;

  final http.Client _client;
  final String _serviceKey;

  static const _host = 'apis.data.go.kr';
  static const _basePath = '/1192136/tideFcstHghLw';

  @override
  Future<TideDay> fetchTideDay(SeaLocation location, DateTime date) async {
    TideRepository.ensureInRange(date);
    // 다지점 보간 지점(khoaStationCodes)은 단일 코드가 null일 수 있다. 이
    // 리포지토리는 실측·예측(시계열) API가 실패했을 때의 2차 폴백이므로,
    // 그런 지점도 합성으로 떨어지지 않게 첫(가장 대표) 관측소를 쓴다.
    // 예전엔 khoaStationCode만 봐서, 다지점 지점은 1차 실패 시 곧장 합성
    // 데이터로 직행하는 구멍이 있었다(무창포 합성 표시 사고의 원인).
    final codes = location.tideStationCodes;
    if (codes.isEmpty) {
      // 범위 초과가 아니라 "이 지점은 아직 실데이터 연동 전"이므로
      // DataRangeException이 아닌 일반 예외로 던져 합성 데이터 폴백을 탄다.
      throw Exception('${location.name}에는 조위관측소 코드가 없습니다');
    }
    final obsCode = codes.first;

    final day = DateTime(date.year, date.month, date.day);
    // 자정 부근 보간을 위해 전날~다음날까지 조회.
    final results = await Future.wait([
      _fetchExtremes(obsCode, day.subtract(const Duration(days: 1))),
      _fetchExtremes(obsCode, day),
      _fetchExtremes(obsCode, day.add(const Duration(days: 1))),
    ]);
    final all = [...results[0], ...results[1], ...results[2]]
      ..sort((a, b) => a.time.compareTo(b.time));
    if (all.isEmpty) {
      throw const FormatException('조석예보 응답에 고저조 데이터가 없음');
    }

    final dayExtremes = all
        .where((e) => !e.time.isBefore(day))
        .where((e) => e.time.isBefore(day.add(const Duration(days: 1))))
        .toList();
    // **당일 것이 하나도 없으면 실패로 친다.** 예전엔 3일 전체가 빈 경우만
    // 막아서, 전날·다음날은 왔는데 당일만 빠지면(간헐적 응답 실패) 그대로
    // "성공"으로 올라갔다. 그러면 화면에 만조·간조 카드가 하나도 없고,
    // 조위 곡선은 마지막 극값으로 25시간 내내 고정돼 조류세기가 0%로 뜬다
    // (2026-08-06 사용자 제보 화면이 정확히 이 상태였다). 여기서 던져야
    // 폴백 체인(고저조 → 합성)이 이어진다.
    if (dayExtremes.isEmpty) {
      throw const FormatException('조석예보에 당일 고저조가 없음');
    }

    return TideDay(
      date: day,
      locationId: location.id,
      extremes: dayExtremes,
      hourlyHeightsCm: interpolateHourlyHeights(all, day),
    );
  }

  Future<List<TideExtreme>> _fetchExtremes(
    String obsCode,
    DateTime date,
  ) async {
    final ymd =
        '${date.year}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
    // 파라미터는 포털 상세기능(요청변수) 화면에서 확정된 규격:
    // serviceKey / pageNo / numOfRows / type / obsCode / reqDate
    final uri = Uri.https(_host, '$_basePath/GetTideFcstHghLwApiService', {
      'serviceKey': _serviceKey,
      'pageNo': '1',
      'numOfRows': '10',
      'type': 'json',
      'obsCode': obsCode,
      'reqDate': ymd,
    });
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw http.ClientException('조석예보 응답 오류 ${res.statusCode}', uri);
    }
    return parseDataGoKrItems(res.body).map(mapTideItem).toList();
  }
}

/// 고저조 응답 item 하나를 [TideExtreme]으로 변환한다.
///
/// 실측(2026-07) 확정 필드:
///   predcDt      예측일시 "yyyy-MM-dd HH:mm"
///   predcTdlvVl  예측조위값 (cm, 숫자)
///   extrSe       극치구분 — 홀수(1,3)=고조, 짝수(2,4)=저조
/// 과거 KHOA 계열 명명(tph_time/tph_level/hl_code 등)도 함께 수용한다.
TideExtreme mapTideItem(Map<String, dynamic> item) {
  final timeRaw = pickField(item, const [
    'predcDt', // 실측 확정
    'tphTime',
    'tph_time',
    'recordTime',
    'record_time',
    'fcstTime',
    'tideTime',
  ]);
  final heightRaw = pickField(item, const [
    'predcTdlvVl', // 실측 확정
    'tph_level',
    'tphLevel',
    'tphHght',
    'tph_hght',
    'tideLevel',
    'tide_level',
    'fcstValue',
    'tphLvl',
  ]);
  final hlRaw = pickField(item, const [
    'extrSe', // 실측 확정
    'hlCode',
    'hl_code',
    'tphType',
    'code',
    'hghLwCd',
  ]);
  if (timeRaw == null || heightRaw == null || hlRaw == null) {
    throw FormatException('알 수 없는 조석예보 필드 구성: ${item.keys.join(', ')}');
  }

  final time = DateTime.parse(timeRaw.toString().replaceFirst(' ', 'T'));
  final height = double.parse(heightRaw.toString());
  final hl = hlRaw.toString();
  final code = int.tryParse(hl);
  final bool isHigh;
  if (code != null) {
    isHigh = code.isOdd; // extrSe: 1·3=고조, 2·4=저조
  } else if (hl.contains('고') || hl.toUpperCase().startsWith('H')) {
    isHigh = true;
  } else if (hl.contains('저') || hl.toUpperCase().startsWith('L')) {
    isHigh = false;
  } else {
    throw FormatException('알 수 없는 고저조 코드: $hl');
  }
  return TideExtreme(time: time, heightCm: height, isHigh: isHigh);
}

/// 시간순 극값 목록에서 [day]의 00~24시 1시간 간격 조위 25개를 코사인 보간한다.
///
/// 인접 극값 A(tA, hA) → B(tB, hB) 사이의 시각 t 조위:
///   h = hA + (hB - hA) * (1 - cos(π * (t-tA)/(tB-tA))) / 2
/// 관측 범위 밖 시각은 가장 가까운 극값으로 고정한다.
List<double> interpolateHourlyHeights(
  List<TideExtreme> sortedExtremes,
  DateTime day,
) {
  double heightAt(DateTime t) {
    if (t.isBefore(sortedExtremes.first.time)) {
      return sortedExtremes.first.heightCm;
    }
    for (var i = 0; i < sortedExtremes.length - 1; i++) {
      final a = sortedExtremes[i];
      final b = sortedExtremes[i + 1];
      if (!t.isBefore(a.time) && t.isBefore(b.time)) {
        final span = b.time.difference(a.time).inMinutes;
        if (span == 0) return a.heightCm;
        final frac = t.difference(a.time).inMinutes / span;
        return a.heightCm +
            (b.heightCm - a.heightCm) * (1 - math.cos(math.pi * frac)) / 2;
      }
    }
    return sortedExtremes.last.heightCm;
  }

  return List<double>.generate(
    25,
    (h) => heightAt(day.add(Duration(hours: h))),
  );
}
