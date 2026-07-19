import 'package:flutter/material.dart';

/// 내장 해안선(Natural Earth) 데이터가 실제 해안보다 약간 동쪽으로 치우쳐
/// 있어, 지도 위 모든 지리 레이어(해안선·지명 라벨)를 이 값만큼 서쪽으로
/// 함께 당겨 그린다. 해안선과 라벨이 **같은 보정값**을 써야 지명이 바다로
/// 밀려나지 않고 육지 위에 얹힌다.
const double kMapLonShift = -0.5;

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

/// 바람 지도의 기본 화면뷰 범위. 북쪽(중국 북부·러시아)은 정보 가치가 낮아
/// 상단을 잘라(뷰를 위로 이동) 한국이 화면에서 조금 더 크게·위쪽에 오도록 한다.
/// 이 뷰는 바람장 격자 범위(minLat 26.5 ~ maxLat 45.5)의 부분집합이므로
/// 히트맵·해안선은 그대로 뷰를 가득 채운다(재추출 불필요).
const mapViewBounds = LatLonBounds(
  minLat: 26.5,
  maxLat: 43.0,
  minLon: 118.5,
  maxLon: 136.5,
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
