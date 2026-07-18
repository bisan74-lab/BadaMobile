import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../locations/data/models/sea_location.dart';
import '../models/land_weather.dart';
import 'land_weather_repository.dart';

/// Open-Meteo 육상 날씨 실데이터 리포지토리(무료·키 불필요·전 세계).
///
/// - Forecast API: 현재값 + 24시간 시간별 + 15일 일별 + 15분 강수(2시간 나우캐스트)
///   기온·날씨코드·강수확률·습도·바람·돌풍·풍향·자외선·가시거리·일출/일몰.
/// - Air-Quality API: PM2.5/PM10/유럽 AQI(공기오염 예측).
///
/// https://open-meteo.com/en/docs
class OpenMeteoLandWeatherRepository implements LandWeatherRepository {
  OpenMeteoLandWeatherRepository({http.Client? client})
    : _client = client ?? http.Client();

  final http.Client _client;

  static const _forecastHost = 'api.open-meteo.com';
  static const _airHost = 'air-quality-api.open-meteo.com';

  @override
  Future<WeatherForecast> fetchForecast(SeaLocation location) async {
    final common = {
      'latitude': location.latitude.toString(),
      'longitude': location.longitude.toString(),
      'timezone': 'Asia/Seoul',
    };

    final forecastUri = Uri.https(_forecastHost, '/v1/forecast', {
      ...common,
      'forecast_days': '16',
      'current':
          'temperature_2m,relative_humidity_2m,apparent_temperature,'
          'weather_code,wind_speed_10m,wind_gusts_10m,wind_direction_10m,'
          'visibility,uv_index',
      'hourly':
          'temperature_2m,weather_code,precipitation_probability,'
          'relative_humidity_2m,wind_speed_10m,wind_gusts_10m,wind_direction_10m',
      'daily':
          'weather_code,temperature_2m_max,temperature_2m_min,'
          'precipitation_probability_max,uv_index_max,sunrise,sunset',
      'minutely_15': 'precipitation,weather_code',
      'wind_speed_unit': 'ms',
      'forecast_minutely_15': '8',
    });
    final airUri = Uri.https(_airHost, '/v1/air-quality', {
      ...common,
      'current': 'pm2_5,pm10,european_aqi',
    });

    final responses = await Future.wait([
      _client.get(forecastUri),
      _client.get(airUri).catchError((_) => http.Response('{}', 200)),
    ]);
    final root = _json(responses[0], forecastUri);

    return WeatherForecast(
      locationId: location.id,
      now: _parseNow(root['current'] as Map<String, dynamic>?),
      hourly: _parseHourly(root['hourly'] as Map<String, dynamic>?),
      daily: _parseDaily(root['daily'] as Map<String, dynamic>?),
      nowcast: _parseNowcast(root['minutely_15'] as Map<String, dynamic>?),
      air: _parseAir(responses[1]),
    );
  }

  Map<String, dynamic> _json(http.Response res, Uri uri) {
    if (res.statusCode != 200) {
      throw http.ClientException('Open-Meteo 응답 오류 ${res.statusCode}', uri);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
  int _i(Object? v) => (v as num?)?.round() ?? 0;

  WeatherNow _parseNow(Map<String, dynamic>? c) {
    if (c == null) throw const FormatException('current 필드 없음');
    return WeatherNow(
      tempC: _d(c['temperature_2m']),
      weatherCode: _i(c['weather_code']),
      humidityPct: _i(c['relative_humidity_2m']),
      windSpeedMs: _d(c['wind_speed_10m']),
      windGustMs: _d(c['wind_gusts_10m']),
      windDirDeg: _d(c['wind_direction_10m']),
      uvIndex: _d(c['uv_index']),
      // Open-Meteo visibility는 m 단위 → km.
      visibilityKm: _d(c['visibility']) / 1000,
      feelsLikeC: _d(c['apparent_temperature']),
    );
  }

  List<double?> _nums(Map<String, dynamic>? b, String k) =>
      ((b?[k] as List?) ?? const [])
          .map((v) => v == null ? null : (v as num).toDouble())
          .toList();

  List<WeatherHour> _parseHourly(Map<String, dynamic>? h) {
    if (h == null) return const [];
    final times = ((h['time'] as List?) ?? const [])
        .map((v) => DateTime.parse(v as String))
        .toList();
    final temp = _nums(h, 'temperature_2m');
    final code = _nums(h, 'weather_code');
    final pop = _nums(h, 'precipitation_probability');
    final hum = _nums(h, 'relative_humidity_2m');
    final wind = _nums(h, 'wind_speed_10m');
    final gust = _nums(h, 'wind_gusts_10m');
    final dir = _nums(h, 'wind_direction_10m');
    double at(List<double?> xs, int i) => i < xs.length ? (xs[i] ?? 0) : 0;
    return [
      for (var i = 0; i < times.length; i++)
        WeatherHour(
          time: times[i],
          tempC: at(temp, i),
          weatherCode: at(code, i).round(),
          precipProbPct: at(pop, i).round(),
          humidityPct: at(hum, i).round(),
          windSpeedMs: at(wind, i),
          windGustMs: at(gust, i),
          windDirDeg: at(dir, i),
        ),
    ];
  }

  List<WeatherDay> _parseDaily(Map<String, dynamic>? d) {
    if (d == null) return const [];
    final dates = ((d['time'] as List?) ?? const [])
        .map((v) => DateTime.parse(v as String))
        .toList();
    final code = _nums(d, 'weather_code');
    final tmax = _nums(d, 'temperature_2m_max');
    final tmin = _nums(d, 'temperature_2m_min');
    final pop = _nums(d, 'precipitation_probability_max');
    final uv = _nums(d, 'uv_index_max');
    final sunrise = (d['sunrise'] as List?) ?? const [];
    final sunset = (d['sunset'] as List?) ?? const [];
    double at(List<double?> xs, int i) => i < xs.length ? (xs[i] ?? 0) : 0;
    DateTime? atT(List xs, int i) =>
        i < xs.length && xs[i] != null ? DateTime.parse(xs[i] as String) : null;
    return [
      for (var i = 0; i < dates.length; i++)
        WeatherDay(
          date: dates[i],
          weatherCode: at(code, i).round(),
          tempMaxC: at(tmax, i),
          tempMinC: at(tmin, i),
          precipProbMaxPct: at(pop, i).round(),
          uvMax: at(uv, i),
          sunrise: atT(sunrise, i),
          sunset: atT(sunset, i),
        ),
    ];
  }

  List<NowcastStep> _parseNowcast(Map<String, dynamic>? m) {
    if (m == null) return const [];
    final times = ((m['time'] as List?) ?? const [])
        .map((v) => DateTime.parse(v as String))
        .toList();
    final precip = _nums(m, 'precipitation');
    final code = _nums(m, 'weather_code');
    final now = DateTime.now();
    final out = <NowcastStep>[];
    for (var i = 0; i < times.length; i++) {
      if (times[i].isBefore(now.subtract(const Duration(minutes: 15)))) {
        continue;
      }
      out.add(
        NowcastStep(
          time: times[i],
          precipMm: i < precip.length ? (precip[i] ?? 0) : 0,
          weatherCode: i < code.length ? (code[i] ?? 0).round() : 0,
        ),
      );
    }
    return out.take(8).toList();
  }

  AirQuality? _parseAir(http.Response res) {
    if (res.statusCode != 200) return null;
    final root = jsonDecode(res.body);
    if (root is! Map<String, dynamic>) return null;
    final c = root['current'];
    if (c is! Map<String, dynamic>) return null;
    if (c['pm2_5'] == null && c['pm10'] == null) return null;
    return AirQuality(
      pm2_5: _d(c['pm2_5']),
      pm10: _d(c['pm10']),
      aqi: (c['european_aqi'] as num?)?.toInt(),
    );
  }
}
