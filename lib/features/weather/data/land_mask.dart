import 'land_polygons_data.dart';

/// 지도 위 임의 좌표가 육지인지 판정한다.
///
/// 판정에는 **닫힌 육지 면**(`landPolygons`, Natural Earth 10m land + minor
/// islands)을 쓴다. 지도에 그리는 해안선(`country_borders_data.dart`)은 bbox로
/// 잘린 **열린 선(LineString)**이라 point-in-polygon에 쓸 수 없다 — 예전에
/// 그걸로 판정했다가 서울이 바다로, 황해 한복판이 육지로 나오는 정반대 결과가
/// 나왔다(사용자 지적: "서해바다인데 파도 정보가 없다"). 판정용 면 데이터는
/// `tool/gen_land.py`로 따로 뽑는다.
///
/// 파랑모델(0.25°≈25km) 격자만으로 판정하지 않는 이유: 삼척·포항·고흥반도처럼
/// 폭이 좁은 지형은 완전한 육지 지점도 격자 반경 안에 바다가 걸려 "육지인데
/// 앞바다 파도값이 나온다"는 문제가 있었다.
bool isOnLand(double lat, double lon) {
  for (final polygon in landPolygons) {
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
