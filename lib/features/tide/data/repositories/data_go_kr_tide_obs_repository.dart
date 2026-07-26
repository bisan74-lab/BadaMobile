import 'package:http/http.dart' as http;

import '../../../../core/config/env.dart';
import '../../../../core/network/data_go_kr.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/tide_data.dart';
import 'tide_repository.dart';

/// 공공데이터포털 「해양수산부 국립해양조사원_조위관측소 실측·예측 조위 조회」
/// (서비스ID SV-AP-02-009, 데이터셋 15142507) 리포지토리.
///
/// 이 API는 관측소별 조위 시계열(실측·예측)을 [min]분 간격으로 준다. 조석예보
/// (고,저조) API가 극값만 주는 것과 달리 연속 곡선을 주므로, **예측 조위 시계열**을
/// 받아 (1) 조위 곡선(hourlyHeightsCm)과 (2) 만조/간조 극값을 만든다. 극값은
/// 시계열의 국소 최대/최소를 이웃 3점 포물선(2차)으로 시·분까지 정밀화한다
/// (격자보다 촘촘한 실제 극값 시각·조위). 값은 과거·미래 일관성을 위해
/// **예측(tdlvHgt) 우선, 없으면 실측(bscTdlvHgt)**으로 고른다.
///
/// 규격(활용가이드 SV-AP-02-009):
/// - URL: https://apis.data.go.kr/1192136/surveyTideLevel/GetSurveyTideLevelApiService
/// - 요청: serviceKey / type=json / obsCode / reqDate(yyyyMMdd) / min(분 간격) /
///   numOfRows(최대 300)
/// - 응답: response.header{resultCode,resultMsg} + response.body.items.item[]
///   각 item: obsvtrNm(관측소)·lat·lot·obsrvnDt(관측일시)·bscTdlvHgt(실측조위 cm)·
///   tdlvHgt(예측조위 cm). resultCode 00=정상, 03=데이터없음.
///
/// serviceKey는 data.go.kr **디코딩 키**를 주입한다(Uri가 재인코딩하므로 인코딩
/// 키를 넣으면 이중 인코딩된다). 봉투·필드명은 [parseDataGoKrItems]/[pickField]로
/// 처리하며 실패 시 예외를 던져 상위 폴백(고저조 API → 합성 데이터)으로 넘어간다.
class DataGoKrTideObsRepository implements TideRepository {
  DataGoKrTideObsRepository({http.Client? client, String? serviceKey})
    : _client = client ?? http.Client(),
      _serviceKey = serviceKey ?? Env.dataGoKrApiKey;

  final http.Client _client;
  final String _serviceKey;

  static const _host = 'apis.data.go.kr';
  static const _path = '/1192136/surveyTideLevel/GetSurveyTideLevelApiService';

  /// 시계열 간격(분). 10분이면 하루 ~144점으로 numOfRows(최대 300) 안에서
  /// 극값 시각을 분 단위로 정밀히 잡을 수 있다.
  static const _stepMinutes = 10;

  @override
  Future<TideDay> fetchTideDay(SeaLocation location, DateTime date) async {
    TideRepository.ensureInRange(date);
    final obsCode = location.khoaStationCode;
    if (obsCode == null) {
      // 범위 초과가 아니라 "이 지점은 아직 실데이터 연동 전"이므로 일반
      // 예외로 던져 합성 데이터 폴백을 탄다.
      throw Exception('${location.name}에는 조위관측소 코드가 없습니다');
    }

    final day = DateTime(date.year, date.month, date.day);
    // 자정 부근 극값·곡선 연속성을 위해 전날~다음날까지 조회해 이어붙인다.
    final series = <_TideSample>[];
    for (final d in [
      day.subtract(const Duration(days: 1)),
      day,
      day.add(const Duration(days: 1)),
    ]) {
      series.addAll(await _fetchSeries(obsCode, d));
    }
    series.sort((a, b) => a.time.compareTo(b.time));
    // 중복 시각 제거(전날 24:00 == 당일 00:00 등).
    final dedup = <_TideSample>[];
    for (final s in series) {
      if (dedup.isEmpty || dedup.last.time != s.time) dedup.add(s);
    }
    if (dedup.length < 3) {
      throw const FormatException('실측·예측 조위 응답에 충분한 시계열이 없음');
    }

    return TideDay(
      date: day,
      locationId: location.id,
      extremes: _extremesFrom(dedup, day),
      hourlyHeightsCm: _hourlyFrom(dedup, day),
    );
  }

  Future<List<_TideSample>> _fetchSeries(String obsCode, DateTime date) async {
    final ymd =
        '${date.year}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
    final uri = Uri.https(_host, _path, {
      'serviceKey': _serviceKey,
      'type': 'json',
      'obsCode': obsCode,
      'reqDate': ymd,
      'min': '$_stepMinutes',
      'numOfRows': '300',
    });
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw http.ClientException('실측·예측 조위 응답 오류 ${res.statusCode}', uri);
    }
    return parseDataGoKrItems(res.body).map(_mapSample).toList();
  }

  /// 시계열 한 행 → (시각, 조위). 조위는 **예측(tdlvHgt) 우선, 없으면
  /// 실측(bscTdlvHgt)**.
  _TideSample _mapSample(Map<String, dynamic> item) {
    final timeRaw = pickField(item, const [
      'obsrvnDt', // 활용가이드 확정: 관측일시
      'record_time',
      'pre_time',
      'recordTime',
      'time',
    ]);
    // 예측 조위 후보 → 실측 조위 후보 순.
    final levelRaw =
        pickField(item, const [
          'tdlvHgt', // 활용가이드 확정: 예측조위(cm)
          'pre_value',
          'predcTdlvVl',
          'preValue',
        ]) ??
        pickField(item, const [
          'bscTdlvHgt', // 활용가이드 확정: 실측조위(cm)
          'tide_level',
          'tdlv',
        ]);
    if (timeRaw == null || levelRaw == null) {
      throw FormatException('알 수 없는 실측·예측 조위 필드 구성: ${item.keys.join(', ')}');
    }
    final time = DateTime.parse(timeRaw.toString().replaceFirst(' ', 'T'));
    final level = double.parse(levelRaw.toString());
    return _TideSample(time: time, heightCm: level);
  }

  /// 시계열에서 [day](00~24시) 구간의 만조/간조를 뽑는다. 격자의 국소 극값을
  /// 찾은 뒤, 이웃 3점 포물선(2차)으로 꼭짓점 시각·높이를 시·분까지 정밀화한다
  /// — 실제 만조/간조는 격자 시각에 딱 맞지 않으므로.
  List<TideExtreme> _extremesFrom(List<_TideSample> s, DateTime day) {
    final next = day.add(const Duration(days: 1));
    final out = <TideExtreme>[];
    for (var i = 1; i < s.length - 1; i++) {
      final y0 = s[i - 1].heightCm, y1 = s[i].heightCm, y2 = s[i + 1].heightCm;
      final isHigh = y1 >= y0 && y1 > y2;
      final isLow = y1 <= y0 && y1 < y2;
      if (!isHigh && !isLow) continue;

      // 포물선 꼭짓점 오프셋(격자 간격 단위, -0.5~0.5). 분모 0이면 평평.
      final denom = y0 - 2 * y1 + y2;
      final d = denom == 0 ? 0.0 : (0.5 * (y0 - y2) / denom).clamp(-0.5, 0.5);
      final halfMs = s[i + 1].time.difference(s[i - 1].time).inMilliseconds / 2;
      final refinedTime = s[i].time.add(
        Duration(milliseconds: (d * halfMs).round()),
      );
      final refinedHeight = y1 - 0.25 * (y0 - y2) * d;

      // 당일(00~24시) 극값만 남긴다.
      if (refinedTime.isBefore(day) || !refinedTime.isBefore(next)) continue;
      out.add(
        TideExtreme(time: refinedTime, heightCm: refinedHeight, isHigh: isHigh),
      );
    }
    return out;
  }

  /// 시계열을 [day] 00~24시 1시간 간격 25점으로 만든다(선형 보간).
  List<double> _hourlyFrom(List<_TideSample> s, DateTime day) {
    double at(DateTime t) {
      if (!t.isAfter(s.first.time)) return s.first.heightCm;
      if (!t.isBefore(s.last.time)) return s.last.heightCm;
      for (var i = 0; i < s.length - 1; i++) {
        final a = s[i], b = s[i + 1];
        if (!t.isBefore(a.time) && t.isBefore(b.time)) {
          final span = b.time.difference(a.time).inMilliseconds;
          if (span == 0) return a.heightCm;
          final f = t.difference(a.time).inMilliseconds / span;
          return a.heightCm + (b.heightCm - a.heightCm) * f;
        }
      }
      return s.last.heightCm;
    }

    return List<double>.generate(25, (h) => at(day.add(Duration(hours: h))));
  }
}

/// 시계열 한 점(내부용).
class _TideSample {
  const _TideSample({required this.time, required this.heightCm});
  final DateTime time;
  final double heightCm;
}
