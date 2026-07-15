import '../../../locations/data/models/sea_location.dart';
import '../models/marine_weather.dart';

/// 해양 기상 데이터 소스 추상화.
///
/// 현재 구현: [MockMarineWeatherRepository]
/// 계획: OpenMeteoMarineRepository — Open-Meteo Marine/Forecast API 연동
abstract class MarineWeatherRepository {
  /// [hours]시간 분량의 시간별 예보를 반환한다.
  Future<MarineForecast> fetchForecast(SeaLocation location, {int hours = 48});
}
