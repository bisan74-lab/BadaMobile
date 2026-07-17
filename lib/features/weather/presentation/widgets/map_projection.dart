import 'package:flutter/material.dart';

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

/// 바람 지도의 기본 화면뷰 범위 — 한반도 중심으로 중국 동해안·일본·대만
/// 일부까지 보이는 정도(윈디 기본 줌 수준 참고).
const mapViewBounds = LatLonBounds(
  minLat: 23.0,
  maxLat: 42.0,
  minLon: 116.0,
  maxLon: 134.0,
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
}
