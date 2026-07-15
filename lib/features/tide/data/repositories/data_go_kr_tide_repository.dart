import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../../../core/config/env.dart';
import '../../../../core/errors/data_errors.dart';
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
    final obsCode = location.khoaStationCode;
    if (obsCode == null) {
      throw DataRangeException('${location.name}에는 조위관측소 코드가 없습니다');
    }

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
/// KHOA 계열 API에서 관찰되는 필드명 후보를 순서대로 시도한다.
TideExtreme mapTideItem(Map<String, dynamic> item) {
  final timeRaw = pickField(item, const [
    'tphTime',
    'tph_time',
    'recordTime',
    'record_time',
    'fcstTime',
    'tideTime',
  ]);
  final heightRaw = pickField(item, const [
    'tph_level', // 바다누리 조석예보 표준 필드
    'tphLevel',
    'tphHght',
    'tph_hght',
    'tideLevel',
    'tide_level',
    'fcstValue',
    'tphLvl',
  ]);
  final hlRaw = pickField(item, const [
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
  final bool isHigh;
  if (hl.contains('고') || hl.toUpperCase().startsWith('H')) {
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
