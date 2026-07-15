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
  }) async {
    final days = (hours / 24).ceil().clamp(1, 16);
    final common = {
      'latitude': location.latitude.toString(),
      'longitude': location.longitude.toString(),
      'timezone': 'Asia/Seoul',
      'forecast_days': days.toString(),
    };

    final marineUri = Uri.https(_marineHost, '/v1/marine', {
      ...common,
      'hourly':
          'wave_height,wave_period,wave_direction,sea_surface_temperature',
    });
    final forecastUri = Uri.https(_forecastHost, '/v1/forecast', {
      ...common,
      'hourly':
          'wind_speed_10m,wind_gusts_10m,wind_direction_10m,'
          'temperature_2m',
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
  final waveHeight = nums(marine, 'wave_height');
  final wavePeriod = nums(marine, 'wave_period');
  final waveDir = nums(marine, 'wave_direction');
  final waterTemp = nums(marine, 'sea_surface_temperature');

  double last(List<double?> xs, int i, double prev) =>
      (i >= 0 && i < xs.length ? xs[i] : null) ?? prev;

  final result = <HourlyMarine>[];
  var pWind = 0.0, pGust = 0.0, pWindDir = 0.0, pAir = 0.0;
  var pWave = 0.0, pPeriod = 0.0, pWaveDir = 0.0, pWater = 0.0;
  for (var i = 0; i < times.length && result.length < maxHours; i++) {
    final mi = marineIndex[times[i]] ?? -1;
    pWind = last(windSpeed, i, pWind);
    pGust = last(windGust, i, pGust);
    pWindDir = last(windDir, i, pWindDir);
    pAir = last(airTemp, i, pAir);
    pWave = last(waveHeight, mi, pWave);
    pPeriod = last(wavePeriod, mi, pPeriod);
    pWaveDir = last(waveDir, mi, pWaveDir);
    pWater = last(waterTemp, mi, pWater);
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
      ),
    );
  }
  if (result.isEmpty) {
    throw const FormatException('Open-Meteo 응답에 시간별 데이터가 없음');
  }
  return result;
}
