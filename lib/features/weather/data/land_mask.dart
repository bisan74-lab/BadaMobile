import '../presentation/widgets/country_borders_data.dart';

/// 지도 위 임의 좌표가 육지인지 판정한다. 지도에 실제로 그려지는 해안선
/// (`countryBorders['해안선']`, Natural Earth 10m — 한반도·주변국·섬 전체를
/// 포함한 닫힌 폴리곤 목록)로 point-in-polygon 판정하므로, 별도 데이터나
/// 외부 호출 없이 화면에 보이는 해안선과 완전히 일치하는 정확한 육지/바다
/// 구분이 된다.
///
/// 파랑모델(0.25°≈25km) 격자 기반 판정 대신 이 방식을 쓰는 이유: 삼척·포항·
/// 고흥반도처럼 폭이 좁은 지형은 완전한 육지 지점도 격자 반경 안에 바다가
/// 걸려, "육지인데 앞바다 파도값이 나온다"는 문제가 있었다(사용자 스크린샷
/// 7장으로 확인 — 대전·안동·원주·광주·전주·부산 시내 등). 해안선 폴리곤
/// 기준이면 이 지점들은 정확히 육지로 걸러지고, 해안에 실제로 인접한 지점만
/// 살아남는다.
bool isOnLand(double lat, double lon) {
  for (final polygon in countryBorders['해안선'] ?? const []) {
    if (_pointInPolygon(lat, lon, polygon)) return true;
  }
  return false;
}

/// 표준 ray-casting 알고리즘. 폴리곤이 닫혀 있지 않아도(첫점≠끝점) 마지막
/// 변을 첫 점으로 자동 연결해 정확히 동작한다.
bool _pointInPolygon(double lat, double lon, List<(double, double)> polygon) {
  if (polygon.length < 3) return false;
  // 바운딩 박스로 먼저 걸러 대부분의(멀리 있는) 폴리곤을 빠르게 스킵한다.
  var minLat = polygon[0].$1, maxLat = polygon[0].$1;
  var minLon = polygon[0].$2, maxLon = polygon[0].$2;
  for (final (plat, plon) in polygon) {
    if (plat < minLat) minLat = plat;
    if (plat > maxLat) maxLat = plat;
    if (plon < minLon) minLon = plon;
    if (plon > maxLon) maxLon = plon;
  }
  if (lat < minLat || lat > maxLat || lon < minLon || lon > maxLon) {
    return false;
  }

  var inside = false;
  var j = polygon.length - 1;
  for (var i = 0; i < polygon.length; i++) {
    final (iLat, iLon) = polygon[i];
    final (jLat, jLon) = polygon[j];
    final intersects =
        ((iLon > lon) != (jLon > lon)) &&
        (lat < (jLat - iLat) * (lon - iLon) / (jLon - iLon) + iLat);
    if (intersects) inside = !inside;
    j = i;
  }
  return inside;
}
