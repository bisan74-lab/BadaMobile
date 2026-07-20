import 'package:flutter/material.dart';

/// 지도 위 모든 지리 레이어(해안선·지명 라벨)에 공통으로 더하는 경도 보정값.
/// 해안선(Natural Earth 50m)과 지명 좌표는 **둘 다 실제 WGS84 위경도**라
/// 보정 없이(0) 그대로 투영하면 서로 정확히 겹치고 실제 지도와도 맞는다.
/// (과거 항구 점 마커 좌표에 맞추려 -0.5°를 줬으나, 그 마커가 부정확했고
/// 지금은 제거돼 보정이 오히려 해안선을 실제보다 서쪽으로 밀었다.)
/// 해안선과 라벨은 **반드시 같은 값**을 써야 어긋나지 않는다.
const double kMapLonShift = 0.0;

/// 위경도 사각 범위.
class LatLonBounds {
  const LatLonBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLon,
    required this.maxLon,
  });

  final double minLat, maxLat, minLon, maxLon;
}

/// 바람 지도의 기본 화면뷰 범위. 한국을 중심으로 동(일본)·서(중국)·남(대만·
/// 오키나와)·북(러시아 연해주)까지 넓게 담아, 확대/이동으로 주변국 해역까지
/// 볼 수 있게 한다. 바람장 격자([OpenMeteoWindFieldRepository])와 같은 범위라
/// 히트맵·해안선이 뷰를 가득 채운다(범위를 바꾸면 격자와 country_borders_data
/// 도 같은 bbox로 다시 맞춰야 한다).
const mapViewBounds = LatLonBounds(
  minLat: 18.0,
  maxLat: 57.0,
  minLon: 108.0,
  maxLon: 148.0,
);

/// [bounds] 안의 위경도를 [size] 크기의 캔버스 좌표로 변환한다.
/// 지도 위 모든 레이어(해안선·히트맵·마커·지명)가 같은 투영을 공유해야
/// 서로 어긋나지 않는다.
class MapProjection {
  const MapProjection(this.bounds, this.size);

  final LatLonBounds bounds;
  final Size size;

  double x(double lon) =>
      (lon - bounds.minLon) / (bounds.maxLon - bounds.minLon) * size.width;

  double y(double lat) =>
      (1 - (lat - bounds.minLat) / (bounds.maxLat - bounds.minLat)) *
      size.height;

  Offset project(double lat, double lon) => Offset(x(lon), y(lat));

  /// [b] 범위가 이 투영 위에서 차지하는 사각형(예: 바람장 격자의 위치).
  Rect rectFor(LatLonBounds b) =>
      Rect.fromLTRB(x(b.minLon), y(b.maxLat), x(b.maxLon), y(b.minLat));

  /// 캔버스 좌표 → 위경도 역변환(지도 탭 지점을 찾을 때 쓴다).
  double lonFor(double x) =>
      bounds.minLon + x / size.width * (bounds.maxLon - bounds.minLon);

  double latFor(double y) =>
      bounds.maxLat - y / size.height * (bounds.maxLat - bounds.minLat);
}
