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
    final days = ((hours - pastDays * 24) / 24).ceil().clamp(1, 16);
    final common = {
      'latitude': location.latitude.toString(),
      'longitude': location.longitude.toString(),
      'timezone': 'Asia/Seoul',
      'forecast_days': days.toString(),
      if (pastDays > 0) 'past_days': pastDays.clamp(0, 92).toString(),
      // **가장 가까운 바다 격자셀**을 강제한다. 연안(강릉·사천진 등)처럼
      // 해안에 붙은 지점은 파랑모델 0.25°(≈25km) 격자에서 가장 가까운 셀이
      // 육지로 마스킹돼 파고·너울이 전부 null→0으로 나왔다(동해 연안에서
      // 파도 0.0). sea를 주면 앞바다 셀 값을 써 실제 파랑이 나오고, 바람도
      // 육지풍이 아니라 앞바다 바람이 잡혀 Windy(해양 기준)와 맞는다.
      'cell_selection': 'sea',
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

    return MarineForecast(
      locationId: location.id,
      hourly: mergeOpenMeteoHourly(
        marine: marine,
        forecast: forecast,
        maxHours: hours,
      ),
    );
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
