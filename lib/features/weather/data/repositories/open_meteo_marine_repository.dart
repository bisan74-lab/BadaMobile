import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../locations/data/models/sea_location.dart';
import '../models/marine_weather.dart';
import 'marine_weather_repository.dart';

/// Open-Meteo 실데이터 리포지토리.
///
/// 두 개의 무료 API(키 불필요)를 좌표 기준으로 호출해 시간축으로 병합한다:
/// - Marine API: 파고·파주기·파향·수온 (최대 16일)
/// - Forecast API: 풍속·돌풍·풍향·기온 (최대 16일)
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
    };

    final marineUri = Uri.https(_marineHost, '/v1/marine', {
      ...common,
      'hourly':
          'wave_height,wave_period,wave_direction,sea_surface_temperature,'
          'wind_wave_height,wind_wave_direction,'
          'swell_wave_height,swell_wave_period,swell_wave_direction,'
          'secondary_swell_wave_height,secondary_swell_wave_period,'
          'secondary_swell_wave_direction',
    });
    final forecastUri = Uri.https(_forecastHost, '/v1/forecast', {
      ...common,
      'hourly':
          'wind_speed_10m,wind_gusts_10m,wind_direction_10m,'
          'temperature_2m,weather_code',
      'wind_speed_unit': 'ms',
    });

    final responses = await Future.wait([
      _client.get(marineUri),
      _client.get(forecastUri),
    ]);
    final marine = _hourlyJson(responses[0], marineUri);
    final forecast = _hourlyJson(responses[1], forecastUri);

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
