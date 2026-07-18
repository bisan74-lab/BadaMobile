import 'package:flutter/material.dart';

import 'map_projection.dart';

/// 지도 위에 위치를 가늠할 수 있도록 표시하는 주요 도시 이름
/// (한국 위주 + 주변국 몇 곳, 윈디 지도의 도시 라벨을 참고했다).
const List<(String name, double lat, double lon)> mapCityLabels = [
  ('서울', 37.5665, 126.9780),
  ('인천', 37.4563, 126.7052),
  ('부산', 35.1796, 129.0756),
  ('목포', 34.8118, 126.3922),
  ('여수', 34.7604, 127.6622),
  ('포항', 36.0190, 129.3435),
  ('강릉', 37.7519, 128.8761),
  ('제주', 33.4996, 126.5312),
  ('평양', 39.0392, 125.7625),
  ('상하이', 31.2304, 121.4737),
  ('후쿠오카', 33.5904, 130.4017),
  ('타이베이', 25.0330, 121.5654),
];

/// 지도 위에 작은 도시 이름 라벨을 찍는다.
class MapCityLabelLayer extends StatelessWidget {
  const MapCityLabelLayer({
    super.key,
    required this.projection,
    required this.scale,
  });

  final MapProjection projection;

  /// 지도의 현재 확대 배율(`InteractiveViewer`). 라벨은 지도와 함께
  /// 확대되지 않고 항상 같은 화면 크기로 보이도록 반대로 축소해 그린다.
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final (name, lat, lon) in mapCityLabels)
          if (lon >= projection.bounds.minLon &&
              lon <= projection.bounds.maxLon &&
              lat >= projection.bounds.minLat &&
              lat <= projection.bounds.maxLat)
            Builder(
              builder: (context) {
                final o = projection.project(lat, lon);
                return Positioned(
                  left: o.dx + 4,
                  top: o.dy - 6,
                  child: Transform.scale(
                    scale: 1 / scale,
                    alignment: Alignment.topLeft,
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 3)],
                      ),
                    ),
                  ),
                );
              },
            ),
      ],
    );
  }
}
