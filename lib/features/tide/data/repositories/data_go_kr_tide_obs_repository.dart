import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../../../../core/config/env.dart';
import '../../../../core/network/data_go_kr.dart';
import '../../../locations/data/models/sea_location.dart';
import '../models/tide_data.dart';
import 'data_go_kr_tide_repository.dart' show interpolateHourlyHeights;
import 'tide_repository.dart';

/// 공공데이터포털 「해양수산부 국립해양조사원_조위관측소 실측·예측 조위 조회」
/// (서비스ID SV-AP-02-009, 데이터셋 15142507) 리포지토리.
///
/// 관측소별 조위 시계열(실측·예측)을 [_stepMinutes]분 간격으로 받아
/// 만조/간조 극값(포물선 보간으로 시·분 정밀화)과 25점 조위 곡선을 만든다.
/// 값은 과거·미래 일관성을 위해 예측(tdlvHgt) 우선, 없으면 실측(bscTdlvHgt).
///
/// **다지점 거리가중 보간**: 지점이 여러 관측소 사이에 있으면
/// ([SeaLocation.khoaStationCodes]) 2~4곳을 받아, 조위 곡선을 그냥 평균하지
/// 않고(위상차로 진폭이 깎임) **매칭되는 만조끼리·간조끼리 시각·조위를
/// 거리가중(1/d²) 평균**한다. 각 관측소 좌표는 응답의 lat/lot에서 읽어 지점
/// 좌표와의 거리로 가중치를 정한다. 단일 관측소면 그 지점 시계열을 그대로 쓴다.
///
/// 규격: URL apis.data.go.kr/1192136/surveyTideLevel/GetSurveyTideLevelApiService,
/// 요청 serviceKey/type=json/obsCode/reqDate(yyyyMMdd)/min/numOfRows,
/// 응답 response.body.items.item[] {obsvtrNm,lat,lot,obsrvnDt,bscTdlvHgt,tdlvHgt}.
class DataGoKrTideObsRepository implements TideRepository {
  DataGoKrTideObsRepository({http.Client? client, String? serviceKey})
    : _client = client ?? http.Client(),
      _serviceKey = serviceKey ?? Env.dataGoKrApiKey;

  final http.Client _client;
  final String _serviceKey;

  static const _host = 'apis.data.go.kr';
  static const _path = '/1192136/surveyTideLevel/GetSurveyTideLevelApiService';

  /// 시계열 간격(분). 10분이면 하루 ~144점(numOfRows 최대 300 안)으로 극값
  /// 시각을 분 단위로 정밀히 잡는다.
  static const _stepMinutes = 10;

  /// 다지점 보간 시 다른 관측소에서 같은 극값으로 인정할 시간 허용오차.
  static const _matchTolerance = Duration(hours: 2);

  @override
  Future<TideDay> fetchTideDay(SeaLocation location, DateTime date) async {
    TideRepository.ensureInRange(date);
    final codes = location.tideStationCodes;
    if (codes.isEmpty) {
      // 범위 초과가 아니라 "이 지점은 아직 실데이터 연동 전"이므로 일반
      // 예외로 던져 합성 데이터 폴백을 탄다.
      throw Exception('${location.name}에는 조위관측소 코드가 없습니다');
    }

    final day = DateTime(date.year, date.month, date.day);
    final stations = <_Station>[];
    for (final code in codes) {
      stations.add(await _fetchStation(code, day, location));
    }

    if (stations.length == 1) {
      // 단일 관측소: 그 지점 시계열을 그대로(더 촘촘한 곡선).
      final s = stations.first.samples;
      return TideDay(
        date: day,
        locationId: location.id,
        extremes: _dayExtremes(_allExtremes(s), day),
        hourlyHeightsCm: _hourlyFromSeries(s, day),
      );
    }

    // 다지점: 거리가중으로 매칭 극값 보간.
    final blended = _blendExtremes(stations, day);
    if (blended.length < 2) {
      throw const FormatException('보간할 극값이 부족함');
    }
    return TideDay(
      date: day,
      locationId: location.id,
      extremes: _dayExtremes(blended, day),
      hourlyHeightsCm: interpolateHourlyHeights(blended, day),
    );
  }

  Future<_Station> _fetchStation(
    String obsCode,
    DateTime day,
    SeaLocation target,
  ) async {
    final samples = <_TideSample>[];
    double? lat, lon;
    for (final d in [
      day.subtract(const Duration(days: 1)),
      day,
      day.add(const Duration(days: 1)),
    ]) {
      final items = await _fetchItems(obsCode, d);
      for (final it in items) {
        // 행 하나가 불량(조위 null 등)이어도 전체를 버리지 않고 건너뛴다 —
        // 예전엔 여기서 예외를 던져 시계열 전체가 실패했고, 2차 폴백 구멍과
        // 겹치면 합성 데이터까지 떨어졌다.
        final sample = _mapSample(it);
        if (sample != null) samples.add(sample);
        lat ??= _numField(it, const ['lat', 'obsLat', 'obs_lat']);
        lon ??= _numField(it, const ['lot', 'lon', 'obsLon', 'obs_lon']);
      }
    }
    samples.sort((a, b) => a.time.compareTo(b.time));
    var dedup = <_TideSample>[];
    for (final s in samples) {
      if (dedup.isEmpty || dedup.last.time != s.time) dedup.add(s);
    }
    if (dedup.length < 3) {
      throw const FormatException('실측·예측 조위 응답에 충분한 시계열이 없음');
    }
    // 지점별 2차항 보정(조석표 표준 기법): 전용 관측소가 없는 항구는 인근
    // 관측소 대비 위상·진폭이 지형에 의해 일정하게 어긋난다. 실측 조석표와
    // 대조해 캘리브레이션한 시간차·조위비를 시계열 자체에 적용한다 —
    // 이후 극값 추출·곡선·보간이 모두 보정된 값 위에서 일관되게 동작한다.
    if (target.tideTimeOffsetMin != 0 || target.tideHeightScale != 1.0) {
      final dt = Duration(minutes: target.tideTimeOffsetMin);
      dedup = [
        for (final s in dedup)
          _TideSample(
            time: s.time.add(dt),
            heightCm: s.heightCm * target.tideHeightScale,
          ),
      ];
    }
    // 거리(km): 관측소 좌표가 없으면 지점 좌표로 대체(가중치 지배).
    final dist = _distKm(
      target.latitude,
      target.longitude,
      lat ?? target.latitude,
      lon ?? target.longitude,
    );
    return _Station(
      samples: dedup,
      weight: 1.0 / math.pow(math.max(dist, 0.5), 2),
    );
  }

  /// 요청 1건 타임아웃. 없으면 서버 지연 시 폴백도 못 타고 화면이 계속 돈다.
  static const _timeout = Duration(seconds: 15);

  /// 하루치 시계열 조회. **부분 실패는 빈 목록으로 삼킨다** — 전날/다음날 중
  /// 하나가 일시 오류여도 나머지 이틀로 극값·곡선을 만들 수 있다(자정 부근
  /// 정밀도만 살짝 떨어짐). 사흘 모두 실패하면 시계열 부족으로 상위에서
  /// 예외가 나 폴백 체인(고저조 → 합성)을 탄다.
  Future<List<Map<String, dynamic>>> _fetchItems(
    String obsCode,
    DateTime date,
  ) async {
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
    try {
      final res = await _client.get(uri).timeout(_timeout);
      if (res.statusCode != 200) return const [];
      return parseDataGoKrItems(res.body);
    } catch (_) {
      return const [];
    }
  }

  /// 시계열 한 행 → (시각, 조위). 조위는 예측(tdlvHgt) 우선, 없으면 실측.
  /// 시각·조위가 없거나 형식이 깨진 행은 null(건너뜀) — 행 단위 결측이 시계열
  /// 전체 실패로 번지지 않게 한다.
  _TideSample? _mapSample(Map<String, dynamic> item) {
    final timeRaw = pickField(item, const [
      'obsrvnDt', // 활용가이드 확정: 관측일시
      'record_time',
      'recordTime',
      'time',
    ]);
    final levelRaw =
        pickField(item, const ['tdlvHgt', 'predcTdlvVl', 'pre_value']) ??
        pickField(item, const ['bscTdlvHgt', 'tide_level', 'tdlv']);
    if (timeRaw == null || levelRaw == null) return null;
    final time = DateTime.tryParse(timeRaw.toString().replaceFirst(' ', 'T'));
    final level = double.tryParse(levelRaw.toString());
    if (time == null || level == null) return null;
    return _TideSample(time: time, heightCm: level);
  }

  static double? _numField(Map<String, dynamic> item, List<String> keys) {
    final v = pickField(item, keys);
    if (v == null) return null;
    return v is num ? v.toDouble() : double.tryParse(v.toString());
  }

  /// 시계열의 국소 최대/최소를 만조/간조로 뽑고, 이웃 3점 포물선으로 꼭짓점
  /// 시각·높이를 시·분까지 정밀화한다.
  List<TideExtreme> _allExtremes(List<_TideSample> s) {
    final out = <TideExtreme>[];
    for (var i = 1; i < s.length - 1; i++) {
      final y0 = s[i - 1].heightCm, y1 = s[i].heightCm, y2 = s[i + 1].heightCm;
      final isHigh = y1 >= y0 && y1 > y2;
      final isLow = y1 <= y0 && y1 < y2;
      if (!isHigh && !isLow) continue;
      final denom = y0 - 2 * y1 + y2;
      final d = denom == 0 ? 0.0 : (0.5 * (y0 - y2) / denom).clamp(-0.5, 0.5);
      final halfMs = s[i + 1].time.difference(s[i - 1].time).inMilliseconds / 2;
      out.add(
        TideExtreme(
          time: s[i].time.add(Duration(milliseconds: (d * halfMs).round())),
          heightCm: y1 - 0.25 * (y0 - y2) * d,
          isHigh: isHigh,
        ),
      );
    }
    return out;
  }

  List<TideExtreme> _dayExtremes(List<TideExtreme> all, DateTime day) {
    final next = day.add(const Duration(days: 1));
    return all
        .where((e) => !e.time.isBefore(day) && e.time.isBefore(next))
        .toList();
  }

  /// 여러 관측소의 극값을 거리가중으로 보간한다. 가장 가까운(가중치 최대)
  /// 관측소를 기준으로 그날±경계의 각 만조/간조를 잡고, 나머지 관측소에서
  /// 같은 종류(만조/간조)의 가장 가까운 극값을 [_matchTolerance] 안에서 찾아
  /// 시각·조위를 가중평균한다(곡선 평균이 아니라 매칭 극값 평균 → 진폭 유지).
  List<TideExtreme> _blendExtremes(List<_Station> stations, DateTime day) {
    final ref = stations.reduce((a, b) => a.weight >= b.weight ? a : b);
    final perStation = [for (final st in stations) _allExtremes(st.samples)];
    final from = day.subtract(const Duration(hours: 6));
    final to = day.add(const Duration(hours: 30));
    final refExtremes = _allExtremes(
      ref.samples,
    ).where((e) => e.time.isAfter(from) && e.time.isBefore(to));

    final blended = <TideExtreme>[];
    for (final e in refExtremes) {
      var wSum = 0.0, tSum = 0.0, hSum = 0.0;
      for (var i = 0; i < stations.length; i++) {
        final match = _nearestSameType(perStation[i], e);
        if (match == null) continue;
        final w = stations[i].weight;
        wSum += w;
        tSum += w * match.time.millisecondsSinceEpoch;
        hSum += w * match.heightCm;
      }
      if (wSum <= 0) continue;
      blended.add(
        TideExtreme(
          time: DateTime.fromMillisecondsSinceEpoch((tSum / wSum).round()),
          heightCm: hSum / wSum,
          isHigh: e.isHigh,
        ),
      );
    }
    blended.sort((a, b) => a.time.compareTo(b.time));
    return blended;
  }

  /// [candidates] 중 [target]과 같은 종류(만조/간조)이면서 시각이 가장 가까운
  /// 극값. 허용오차([_matchTolerance]) 밖이면 null.
  TideExtreme? _nearestSameType(
    List<TideExtreme> candidates,
    TideExtreme target,
  ) {
    TideExtreme? best;
    var bestDiff = _matchTolerance;
    for (final c in candidates) {
      if (c.isHigh != target.isHigh) continue;
      final diff = c.time.difference(target.time).abs();
      if (diff <= bestDiff) {
        bestDiff = diff;
        best = c;
      }
    }
    return best;
  }

  /// 시계열을 [day] 00~24시 1시간 간격 25점으로 만든다(선형 보간).
  List<double> _hourlyFromSeries(List<_TideSample> s, DateTime day) {
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

/// 두 위경도 사이 거리(km, 등거리 근사 — 100km 이내 관측소 선택엔 충분).
double _distKm(double lat1, double lon1, double lat2, double lon2) {
  final mLat = (lat1 + lat2) / 2 * math.pi / 180;
  final dx = (lon2 - lon1) * math.cos(mLat) * 111.32;
  final dy = (lat2 - lat1) * 111.32;
  return math.sqrt(dx * dx + dy * dy);
}

/// 한 관측소의 시계열 + 지점까지의 거리가중치(1/d²).
class _Station {
  const _Station({required this.samples, required this.weight});
  final List<_TideSample> samples;
  final double weight;
}

/// 시계열 한 점(내부용).
class _TideSample {
  const _TideSample({required this.time, required this.heightCm});
  final DateTime time;
  final double heightCm;
}
