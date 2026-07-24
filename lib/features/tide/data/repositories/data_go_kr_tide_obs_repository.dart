import 'package:http/http.dart' as http;

import '../../../../core/config/env.dart';
import '../../../../core/network/data_go_kr.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/tide_data.dart';
import 'tide_repository.dart';

/// 공공데이터포털 「해양수산부 국립해양조사원_조위관측소 실측·예측 조위 조회」
/// 리포지토리 (data.go.kr 데이터셋 15142507, 활용신청 승인).
///
/// 이 API는 관측소별 **1시간 간격 1일치** 조위 시계열을 준다 — 실측(과거)과
/// 예측(미래·오늘)이 함께 온다. 조석예보(고,저조) API가 극값만 주는 것과 달리
/// 연속 곡선을 주므로, 우리는 **예측 조위 시계열**을 받아
/// (1) 조위 곡선(hourlyHeightsCm)은 그대로,
/// (2) 만조/간조(극값)는 시계열의 국소 최대/최소를 **포물선 보간으로 시분까지
///     정밀화**해 만든다(1시간 격자보다 촘촘한 실제 극값 시각·조위).
/// 미래 날짜엔 실측이 비어 예측만 오므로, 과거·미래를 일관되게 다루려고 값은
/// **예측 우선, 없으면 실측**으로 고른다.
///
/// 요청변수(포털 상세기능 규격): ServiceKey / ObsCode / Date(yyyyMMdd) /
/// ResultType(json). 응답 봉투·필드명은 KHOA 바다누리(result.data)와 data.go.kr
/// 표준(response.body.items.item)을 모두 수용하고([parseDataGoKrItems]),
/// 필드명 camel/snake 변형도 후보 매칭으로 흡수한다([pickField]). 매핑 실패 시
/// 예외를 던져 상위 폴백(고저조 API → 합성 데이터)으로 넘어간다.
///
/// 참고: data.go.kr가 바다누리 API를 대체하는 신규 엔드포인트를 별도 경로로
/// 제공하면 [_host]/[_path]만 그에 맞춰 바꾸면 되고, 파싱은 그대로 동작한다.
class DataGoKrTideObsRepository implements TideRepository {
  DataGoKrTideObsRepository({http.Client? client, String? serviceKey})
    : _client = client ?? http.Client(),
      _serviceKey = serviceKey ?? Env.dataGoKrApiKey;

  final http.Client _client;
  final String _serviceKey;

  // 바다누리 해양정보 서비스 조위관측소 실측·예측 조위(tideObsPreTab).
  // data.go.kr 15142507이 문서화한 요청주소와 동일 규격이다.
  static const _host = 'www.khoa.go.kr';
  static const _path = '/api/oceangrid/tideObsPreTab/search.do';

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
    final uri = Uri.http(_host, _path, {
      'ServiceKey': _serviceKey,
      'ObsCode': obsCode,
      'Date': ymd,
      'ResultType': 'json',
    });
    final res = await _client.get(uri);
    if (res.statusCode != 200) {
      throw http.ClientException('실측·예측 조위 응답 오류 ${res.statusCode}', uri);
    }
    return parseDataGoKrItems(res.body).map(_mapSample).toList();
  }

  /// 시계열 한 행 → (시각, 조위). 조위는 **예측 우선, 없으면 실측**.
  _TideSample _mapSample(Map<String, dynamic> item) {
    final timeRaw = pickField(item, const [
      'record_time', // 바다누리 실측·예측 공통 관측시각
      'pre_time',
      'obsrDt',
      'predcDt',
      'recordTime',
      'tph_time',
      'time',
    ]);
    // 예측 조위 후보 → 실측 조위 후보 순.
    final levelRaw =
        pickField(item, const [
          'pre_value', // 바다누리 예측 조위(cm)
          'predcTdlvVl',
          'predc_tdlv_vl',
          'preValue',
          'pre_level',
        ]) ??
        pickField(item, const [
          'tide_level', // 실측 조위(cm)
          'tdlv',
          'obsrTdlvVl',
          'tphLevel',
          'tph_level',
        ]);
    if (timeRaw == null || levelRaw == null) {
      throw FormatException('알 수 없는 실측·예측 조위 필드 구성: ${item.keys.join(', ')}');
    }
    final time = DateTime.parse(timeRaw.toString().replaceFirst(' ', 'T'));
    final level = double.parse(levelRaw.toString());
    return _TideSample(time: time, heightCm: level);
  }

  /// 시계열에서 [day](00~24시) 구간의 만조/간조를 뽑는다. 1시간 격자의 국소
  /// 극값을 찾은 뒤, 이웃 3점 포물선(2차)으로 꼭짓점 시각·높이를 시분까지
  /// 정밀화한다 — 실제 만조/간조는 정시에 딱 맞지 않으므로.
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
      final stepMs = s[i + 1].time.difference(s[i - 1].time).inMilliseconds / 2;
      final refinedTime = s[i].time.add(
        Duration(milliseconds: (d * stepMs).round()),
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

  /// 시계열을 [day] 00~24시 1시간 간격 25점으로 만든다(선형 보간). 시계열이
  /// 이미 1시간 격자면 정시값을 그대로 쓰고, 어긋나면 인접값으로 보간한다.
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
