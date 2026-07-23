import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../locations/data/models/sea_location.dart';
import '../models/marine_weather.dart';
import 'marine_weather_repository.dart';

/// Open-Meteo 실데이터 리포지토리.
///
/// 무료 API(키 불필요)를 좌표 기준으로 네 번 호출해 시간축으로 병합한다:
/// - Marine API(파고, `models=ecmwf_wam025`): Windy와 같은 ECMWF WAM 파고
///   (약 10일까지) — 앞 구간은 이 값으로 Windy와 맞춘다.
/// - Marine API(파고, `models=ncep_gfswave025`): NOAA GFS Wave 파고(16일) —
///   ECMWF WAM 예보가 끝나는 10일 이후 꼬리 구간을 이 값으로 채운다.
/// - Marine API(수온, 기본 모델): sea_surface_temperature만 별도 호출
/// - Forecast API(`models=ecmwf_ifs025`): 풍속·돌풍·풍향·기온 (최대 16일)
///
/// 파고 필드는 시각별로 **ECMWF WAM 우선, 없으면 GFS Wave**로 병합한다
/// (사용자 요구: 10일까진 Windy와 값 맞추고, 그 뒤는 기존 16일 예보 유지).
///
/// https://open-meteo.com/en/docs/marine-weather-api
class OpenMeteoMarineRepository implements MarineWeatherRepository {
  OpenMeteoMarineRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const _marineHost = 'marine-api.open-meteo.com';
  static const _forecastHost = 'api.open-meteo.com';

  @override
  Future<MarineForecast> fetchForecast(
    SeaLocation location, {
    int hours = defaultForecastHours,
    int pastDays = 0,
  }) async {
    final (forecast, wavesPresent) = await _fetchAt(
      location.latitude,
      location.longitude,
      location.id,
      hours,
      pastDays,
    );
    // 파랑모델 0.25°(≈25km) 격자에서 탭 지점의 가장 가까운 셀이 육지로
    // 마스킹돼 파고가 전부 null→0으로 나오는 연안 지점(강릉·사천진 등)이
    // 있다(Open-Meteo cell_selection=sea가 이 파랑모델엔 안 먹힌다). 그러면
    // 가장 가까운 **실제 바다 격자**를 찾아 그 지점으로 예보 전체(파고·바람)를
    // 다시 받는다 — Windy가 앞바다 값을 보여주는 것과 같은 효과.
    if (wavesPresent) return forecast;
    final wet = await _nearestWetPoint(location.latitude, location.longitude);
    if (wet == null) return forecast; // 앞바다를 못 찾으면(내륙 등) 원래 결과.
    final (wetForecast, _) = await _fetchAt(
      wet.$1,
      wet.$2,
      location.id,
      hours,
      pastDays,
    );
    return wetForecast;
  }

  /// (lat, lon)에서 예보를 받아 [MarineForecast]와 **실제 파고 데이터가
  /// 있었는지**(false면 연안 육지 마스킹)를 함께 돌려준다.
  Future<(MarineForecast, bool)> _fetchAt(
    double lat,
    double lon,
    String locationId,
    int hours,
    int pastDays,
  ) async {
    final days = ((hours - pastDays * 24) / 24).ceil().clamp(1, 16);
    final common = {
      'latitude': lat.toString(),
      'longitude': lon.toString(),
      'timezone': 'Asia/Seoul',
      'forecast_days': days.toString(),
      if (pastDays > 0) 'past_days': pastDays.clamp(0, 92).toString(),
    };

    // 파고는 Windy와 같은 ECMWF WAM을 우선 쓰고, WAM 예보 한계(약 10일) 뒤는
    // 16일까지 있는 NOAA GFS Wave로 채운다. WAM 요청은 **두 개로 쪼갠다**:
    // - 총 파고(유의파고): wave_height/period/direction — 거의 확실히 지원.
    //   Windy의 '파도'와 맞추는 핵심.
    // - 너울 성분: swell_wave_height/period/direction — Open-Meteo의 ECMWF WAM이
    //   지원하면 Windy의 '너울1/주기'와도 맞고, 지원 안 하면(400) 조용히
    //   GFS 너울로 폴백한다(부가 소스).
    // 한 요청에 묶으면 한 필드라도 미지원 시 요청 전체가 실패해 총 파고까지
    // 잃으므로 분리한다. wind_wave·2차 너울은 GFS 전용으로 둔다.
    const wamTotalFields = 'wave_height,wave_period,wave_direction';
    const wamSwellFields =
        'swell_wave_height,swell_wave_period,swell_wave_direction';
    final marineWamTotalUri = Uri.https(_marineHost, '/v1/marine', {
      ...common,
      'hourly': wamTotalFields,
      'models': 'ecmwf_wam025',
    });
    final marineWamSwellUri = Uri.https(_marineHost, '/v1/marine', {
      ...common,
      'hourly': wamSwellFields,
      'models': 'ecmwf_wam025',
    });
    final marineGfsUri = Uri.https(_marineHost, '/v1/marine', {
      ...common,
      'hourly':
          '$wamTotalFields,$wamSwellFields,'
          'wind_wave_height,wind_wave_direction,'
          'secondary_swell_wave_height,secondary_swell_wave_period,'
          'secondary_swell_wave_direction',
      'models': 'ncep_gfswave025',
    });
    final marineSstUri = Uri.https(_marineHost, '/v1/marine', {
      ...common,
      'hourly': 'sea_surface_temperature',
    });
    // 바람은 지도 바람장(OpenMeteoWindFieldRepository·fetch_wind.py)과 **같은
    // 모델(ecmwf_ifs025)**로 고정한다. 모델을 안 주면 best_match가 되는데,
    // 다도해 같은 연안점에선 고해상도 지역모델을 골라 국지 차폐로 지속풍이
    // 낮게(예: 2~3m/s) 나오는 반면 돌풍은 비슷해, Windy(ECMWF) 및 우리 지도
    // 커서값과 표의 '바람' 수치가 어긋났다(사용자 지적). ECMWF로 맞추면
    // Windy와도, 우리 지도와도 일관된다.
    final forecastUri = Uri.https(_forecastHost, '/v1/forecast', {
      ...common,
      'hourly':
          'wind_speed_10m,wind_gusts_10m,wind_direction_10m,'
          'temperature_2m,weather_code',
      'wind_speed_unit': 'ms',
      'models': 'ecmwf_ifs025',
    });

    final responses = await Future.wait([
      _client.get(marineGfsUri),
      _client.get(marineWamTotalUri),
      _client.get(marineWamSwellUri),
      _client.get(marineSstUri),
      _client.get(forecastUri),
    ]);
    final marineGfs = _hourlyJson(responses[0], marineGfsUri);
    // WAM은 부가 소스라 실패해도 전체를 막지 않는다(그러면 GFS만으로 동작).
    final marineWamTotal = _hourlyJsonOrEmpty(responses[1]);
    final marineWamSwell = _hourlyJsonOrEmpty(responses[2]);
    final marineSst = _hourlyJson(responses[3], marineSstUri);
    final forecast = _hourlyJson(responses[4], forecastUri);
    // GFS를 바탕으로 WAM 총 파고 → WAM 너울을 차례로 덮는다(둘 다 없으면 GFS).
    var mergedWave = _mergeWaveModels(
      marineGfs,
      marineWamTotal,
      wamTotalFields.split(','),
    );
    mergedWave = _mergeWaveModels(
      mergedWave,
      marineWamSwell,
      wamSwellFields.split(','),
    );
    final marine = {
      ...mergedWave,
      'sea_surface_temperature': marineSst['sea_surface_temperature'],
    };

    // 이 지점에 **양(+)의 파고**가 하나라도 있었는지(GFS 또는 WAM 총 파고).
    // 연안 육지 마스킹 셀은 null이 아니라 **0.0**을 돌려주기도 해서, null만
    // 거르면(≠null) 0.0을 유효 데이터로 오인해 앞바다 재조회가 안 됐다
    // (동해 연안 파도 계속 0.0). 그래서 '0보다 큰 값'이 있는지로 판정한다.
    bool anyPositive(Map<String, dynamic> m) =>
        (m['wave_height'] as List?)?.any((v) => v != null && (v as num) > 0) ??
        false;
    final wavesPresent = anyPositive(marineGfs) || anyPositive(marineWamTotal);

    return (
      MarineForecast(
        locationId: locationId,
        hourly: mergeOpenMeteoHourly(
          marine: marine,
          forecast: forecast,
          maxHours: hours,
        ),
      ),
      wavesPresent,
    );
  }

  /// 오름차순 반경으로 8방위를 넓혀가며, 파고 데이터가 있는(=실제 바다 격자)
  /// 가장 가까운 지점을 찾는다. 못 찾으면 null(내륙 등). 한 반경의 8방위는
  /// 병렬로 재빨리 탐색하고, 먼저 걸리는 방위(연안 기준 대개 앞바다 쪽)를
  /// 고른다. 파고 유무만 보는 가벼운 단일 필드 요청이라 부담이 작다.
  Future<(double, double)?> _nearestWetPoint(double lat, double lon) async {
    const radii = [0.3, 0.6, 1.0];
    // (dLat, dLon): 동·서·북·남 먼저(대개 연안의 앞바다 방향), 그다음 대각.
    const dirs = [
      (0.0, 1.0),
      (0.0, -1.0),
      (1.0, 0.0),
      (-1.0, 0.0),
      (1.0, 1.0),
      (1.0, -1.0),
      (-1.0, 1.0),
      (-1.0, -1.0),
    ];
    for (final r in radii) {
      final cands = [
        for (final (dLat, dLon) in dirs) (lat + dLat * r, lon + dLon * r),
      ];
      final wet = await Future.wait(cands.map((c) => _hasWaves(c.$1, c.$2)));
      for (var i = 0; i < cands.length; i++) {
        if (wet[i]) return cands[i];
      }
    }
    return null;
  }

  /// (lat, lon)의 파랑모델 격자에 실제 파고 데이터가 있는지(=바다) 가볍게
  /// 확인한다. 1일치 wave_height 단일 필드만 받아 **0보다 큰 값**이 하나라도
  /// 있으면 true(육지 마스킹 셀은 0.0을 주므로 0은 바다로 치지 않는다).
  /// 어떤 모델이든 데이터가 있으면 잡도록 모델을 지정하지 않는다(best_match).
  /// 실패는 false로 처리(없는 것으로 간주).
  Future<bool> _hasWaves(double lat, double lon) async {
    final uri = Uri.https(_marineHost, '/v1/marine', {
      'latitude': lat.toStringAsFixed(3),
      'longitude': lon.toStringAsFixed(3),
      'hourly': 'wave_height',
      'forecast_days': '1',
      'timezone': 'Asia/Seoul',
    });
    try {
      final res = await _client.get(uri);
      if (res.statusCode != 200) return false;
      final body = jsonDecode(res.body);
      final hourly = body is Map ? body['hourly'] : null;
      final wh = hourly is Map ? hourly['wave_height'] as List? : null;
      return wh != null && wh.any((v) => v != null && (v as num) > 0);
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _hourlyJson(http.Response res, Uri uri) {
    if (res.statusCode != 200) {
      throw http.ClientException('Open-Meteo 응답 오류 ${res.statusCode}', uri);
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final hourly = body['hourly'];
    if (hourly is! Map<String, dynamic>) {
      throw const FormatException('hourly 필드가 없는 Open-Meteo 응답');
    }
    return hourly;
  }

  /// 실패(오류 응답·잘못된 형식)해도 예외를 던지지 않고 빈 맵을 돌려준다 —
  /// 부가 소스(ECMWF WAM)가 죽어도 필수 소스(GFS)만으로 계속 동작하게.
  Map<String, dynamic> _hourlyJsonOrEmpty(http.Response res) {
    try {
      if (res.statusCode != 200) return const {};
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final hourly = body['hourly'];
      return hourly is Map<String, dynamic> ? hourly : const {};
    } catch (_) {
      return const {};
    }
  }
}

/// 파고 두 모델(우선 [primary]=ECMWF WAM, 대체 [secondary]=GFS Wave)을 시각별로
/// 병합한다. [keys] 각 필드에 대해, 같은 시각의 WAM 값이 있으면 그걸, 없으면
/// (WAM 예보 한계 밖·필드 미지원 등) GFS 값을 쓴다. 반환 맵은 [secondary]의
/// 시간축(GFS, 16일 전체)을 기준으로 삼고 GFS 전용 필드(2차 너울 등)도 그대로
/// 담는다. 두 모델은 같은 좌표·timezone·forecast_days로 요청하지만, 안전하게
/// 인덱스가 아니라 시각 문자열로 맞춘다.
Map<String, dynamic> _mergeWaveModels(
  Map<String, dynamic> secondary,
  Map<String, dynamic> primary,
  List<String> keys,
) {
  final baseTimes = (secondary['time'] as List?) ?? const [];
  final primTimes = (primary['time'] as List?) ?? const [];
  final primIndex = {
    for (var i = 0; i < primTimes.length; i++) primTimes[i]: i,
  };

  final out = Map<String, dynamic>.from(secondary);
  for (final key in keys) {
    final primVals = (primary[key] as List?) ?? const [];
    if (primVals.isEmpty) continue; // WAM이 이 필드를 안 주면 GFS 그대로.
    final baseVals = (secondary[key] as List?) ?? const [];
    out[key] = [
      for (var i = 0; i < baseTimes.length; i++)
        () {
          final pi = primIndex[baseTimes[i]];
          final pv = (pi != null && pi < primVals.length) ? primVals[pi] : null;
          return pv ?? (i < baseVals.length ? baseVals[i] : null);
        }(),
    ];
  }
  return out;
}

/// Marine/Forecast 두 응답의 `hourly` 블록을 시간축 기준으로 병합한다.
///
/// 두 API 모두 같은 timezone·forecast_days로 요청하므로 보통 시간축이
/// 일치하지만, 안전하게 forecast의 시간축을 기준으로 marine 값을 조회한다.
/// null 값(예보 범위 밖)은 직전 값으로 채우고, 처음부터 null이면 0을 쓴다.
List<HourlyMarine> mergeOpenMeteoHourly({
  required Map<String, dynamic> marine,
  required Map<String, dynamic> forecast,
  required int maxHours,
}) {
  List<double?> nums(Map<String, dynamic> block, String key) =>
      ((block[key] as List?) ?? const [])
          .map((v) => v == null ? null : (v as num).toDouble())
          .toList();

  final times = ((forecast['time'] as List?) ?? const [])
      .map((v) => DateTime.parse(v as String))
      .toList();
  final marineTimes = ((marine['time'] as List?) ?? const [])
      .map((v) => DateTime.parse(v as String))
      .toList();
  final marineIndex = {
    for (var i = 0; i < marineTimes.length; i++) marineTimes[i]: i,
  };

  final windSpeed = nums(forecast, 'wind_speed_10m');
  final windGust = nums(forecast, 'wind_gusts_10m');
  final windDir = nums(forecast, 'wind_direction_10m');
  final airTemp = nums(forecast, 'temperature_2m');
  final weatherCode = nums(forecast, 'weather_code');
  final waveHeight = nums(marine, 'wave_height');
  final wavePeriod = nums(marine, 'wave_period');
  final waveDir = nums(marine, 'wave_direction');
  final waterTemp = nums(marine, 'sea_surface_temperature');
  final swellHeight = nums(marine, 'swell_wave_height');
  final swellPeriod = nums(marine, 'swell_wave_period');
  final swellDir = nums(marine, 'swell_wave_direction');
  final windWaveHeight = nums(marine, 'wind_wave_height');
  final windWaveDir = nums(marine, 'wind_wave_direction');
  final swell2Height = nums(marine, 'secondary_swell_wave_height');
  final swell2Period = nums(marine, 'secondary_swell_wave_period');
  final swell2Dir = nums(marine, 'secondary_swell_wave_direction');

  double last(List<double?> xs, int i, double prev) =>
      (i >= 0 && i < xs.length ? xs[i] : null) ?? prev;

  // Marine(파고) 모델은 바람 예보(16일)보다 예보 한계가 짧다. Open-Meteo는
  // 모델 범위를 넘어선 시각도 time 축엔 그대로 넣고 값만 null로 돌려주므로,
  // 그냥 두면 파고 등이 직전 값으로 굳은 채(스테일) 표에 계속 노출된다.
  // 파고가 실제로 있는 마지막 시각을 예보 한계로 잡아, 그 뒤 시각은
  // 표에서 아예 뺀다(예보 불가 날짜 삭제).
  DateTime? marineHorizon;
  for (var mi = waveHeight.length - 1; mi >= 0; mi--) {
    if (waveHeight[mi] != null && mi < marineTimes.length) {
      marineHorizon = marineTimes[mi];
      break;
    }
  }

  final result = <HourlyMarine>[];
  var pWind = 0.0, pGust = 0.0, pWindDir = 0.0, pAir = 0.0, pCode = 0.0;
  var pWave = 0.0, pPeriod = 0.0, pWaveDir = 0.0, pWater = 0.0;
  var pSwell = 0.0, pSwellPeriod = 0.0, pSwellDir = 0.0;
  var pWindWave = 0.0, pWindWaveDir = 0.0;
  var pSwell2 = 0.0, pSwell2Period = 0.0, pSwell2Dir = 0.0;
  for (var i = 0; i < times.length && result.length < maxHours; i++) {
    // 파고 예보 한계를 넘는 시각은 표에서 제외한다(위 marineHorizon 참고).
    if (marineHorizon != null && times[i].isAfter(marineHorizon)) break;
    final mi = marineIndex[times[i]] ?? -1;
    pWind = last(windSpeed, i, pWind);
    pGust = last(windGust, i, pGust);
    pWindDir = last(windDir, i, pWindDir);
    pAir = last(airTemp, i, pAir);
    pCode = last(weatherCode, i, pCode);
    pWave = last(waveHeight, mi, pWave);
    pPeriod = last(wavePeriod, mi, pPeriod);
    pWaveDir = last(waveDir, mi, pWaveDir);
    pWater = last(waterTemp, mi, pWater);
    pSwell = last(swellHeight, mi, pSwell);
    pSwellPeriod = last(swellPeriod, mi, pSwellPeriod);
    pSwellDir = last(swellDir, mi, pSwellDir);
    pWindWave = last(windWaveHeight, mi, pWindWave);
    pWindWaveDir = last(windWaveDir, mi, pWindWaveDir);
    pSwell2 = last(swell2Height, mi, pSwell2);
    pSwell2Period = last(swell2Period, mi, pSwell2Period);
    pSwell2Dir = last(swell2Dir, mi, pSwell2Dir);
    result.add(
      HourlyMarine(
        time: times[i],
        windSpeedMs: pWind,
        windGustMs: pGust,
        windDirectionDeg: pWindDir,
        waveHeightM: pWave,
        wavePeriodS: pPeriod,
        waveDirectionDeg: pWaveDir,
        waterTempC: pWater,
        airTempC: pAir,
        swellHeightM: pSwell,
        swellPeriodS: pSwellPeriod,
        windWaveHeightM: pWindWave,
        windWaveDirectionDeg: pWindWaveDir,
        swellDirectionDeg: pSwellDir,
        swell2HeightM: pSwell2,
        swell2PeriodS: pSwell2Period,
        swell2DirectionDeg: pSwell2Dir,
        weatherCode: pCode.round(),
      ),
    );
  }
  if (result.isEmpty) {
    throw const FormatException('Open-Meteo 응답에 시간별 데이터가 없음');
  }
  return result;
}
