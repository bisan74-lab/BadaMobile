import 'package:flutter/material.dart';

import 'map_projection.dart';

/// 지도 위 도시/지역 라벨. `rank`가 작을수록 낮은 배율(멀리서)에도 보인다 —
/// 지도 앱처럼 큰 도시부터 나타나고 확대할수록 더 많은 지역이 드러난다.
typedef CityLabel = ({String name, double lat, double lon, int rank});

const List<CityLabel> mapCityLabels = [
  // rank 1 — 특별시·광역시·주변국 대도시(기본 배율에서 항상 표시).
  (name: '서울', lat: 37.5665, lon: 126.9780, rank: 1),
  (name: '인천', lat: 37.4563, lon: 126.7052, rank: 1),
  (name: '부산', lat: 35.1796, lon: 129.0756, rank: 1),
  (name: '대구', lat: 35.8714, lon: 128.6014, rank: 1),
  (name: '대전', lat: 36.3504, lon: 127.3845, rank: 1),
  (name: '광주', lat: 35.1595, lon: 126.8526, rank: 1),
  (name: '울산', lat: 35.5384, lon: 129.3114, rank: 1),
  (name: '제주', lat: 33.4996, lon: 126.5312, rank: 1),
  (name: '강릉', lat: 37.7519, lon: 128.8761, rank: 1),
  (name: '평양', lat: 39.0392, lon: 125.7625, rank: 1),
  (name: '후쿠오카', lat: 33.5904, lon: 130.4017, rank: 1),

  // rank 2 — 도청소재지·중소도시(조금 확대하면 표시).
  (name: '수원', lat: 37.2636, lon: 127.0286, rank: 2),
  (name: '춘천', lat: 37.8813, lon: 127.7300, rank: 2),
  (name: '청주', lat: 36.6424, lon: 127.4890, rank: 2),
  (name: '전주', lat: 35.8242, lon: 127.1480, rank: 2),
  (name: '창원', lat: 35.2280, lon: 128.6811, rank: 2),
  (name: '포항', lat: 36.0190, lon: 129.3435, rank: 2),
  (name: '목포', lat: 34.8118, lon: 126.3922, rank: 2),
  (name: '여수', lat: 34.7604, lon: 127.6622, rank: 2),
  (name: '천안', lat: 36.8151, lon: 127.1139, rank: 2),
  (name: '원주', lat: 37.3422, lon: 127.9202, rank: 2),
  (name: '안동', lat: 36.5684, lon: 128.7294, rank: 2),
  (name: '세종', lat: 36.4800, lon: 127.2890, rank: 2),
  (name: '군산', lat: 35.9676, lon: 126.7369, rank: 2),
  (name: '통영', lat: 34.8544, lon: 128.4331, rank: 2),
  (name: '경주', lat: 35.8562, lon: 129.2247, rank: 2),
  (name: '속초', lat: 38.2070, lon: 128.5918, rank: 2),

  // rank 3 — 소도시·군(많이 확대해야 표시).
  (name: '서산', lat: 36.7848, lon: 126.4503, rank: 3),
  (name: '보령', lat: 36.3333, lon: 126.6127, rank: 3),
  (name: '태안', lat: 36.7456, lon: 126.2980, rank: 3),
  (name: '홍성', lat: 36.6013, lon: 126.6608, rank: 3),
  (name: '구미', lat: 36.1195, lon: 128.3446, rank: 3),
  (name: '순천', lat: 34.9506, lon: 127.4872, rank: 3),
  (name: '진주', lat: 35.1800, lon: 128.1076, rank: 3),
  (name: '영덕', lat: 36.4150, lon: 129.3656, rank: 3),
  (name: '울진', lat: 36.9930, lon: 129.4005, rank: 3),
  (name: '남해', lat: 34.8376, lon: 127.8925, rank: 3),
  (name: '완도', lat: 34.3110, lon: 126.7550, rank: 3),
  (name: '진도', lat: 34.4867, lon: 126.2634, rank: 3),
  (name: '고흥', lat: 34.6053, lon: 127.2850, rank: 3),
  (name: '부안', lat: 35.7317, lon: 126.7330, rank: 3),
  (name: '삼척', lat: 37.4497, lon: 129.1655, rank: 3),
  (name: '양양', lat: 38.0754, lon: 128.6190, rank: 3),
];

/// 지도 위에 도시 이름 라벨을 확대 단계별로 찍는다(지도 앱 스타일).
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

  /// rank별 라벨 노출 임계 배율.
  static double _threshold(int rank) => switch (rank) {
    1 => 1.0,
    2 => 2.0,
    _ => 3.4,
  };

  @override
  Widget build(BuildContext context) {
    final b = projection.bounds;
    return Stack(
      children: [
        for (final c in mapCityLabels)
          if (scale >= _threshold(c.rank) &&
              c.lon >= b.minLon &&
              c.lon <= b.maxLon &&
              c.lat >= b.minLat &&
              c.lat <= b.maxLat)
            Builder(
              builder: (context) {
                final o = projection.project(c.lat, c.lon);
                return Positioned(
                  left: o.dx,
                  top: o.dy,
                  child: Transform.scale(
                    scale: 1 / scale,
                    alignment: Alignment.center,
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, -0.5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 4,
                            height: 4,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(color: Colors.black54, blurRadius: 2),
                              ],
                            ),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            c.name,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: c.rank == 1 ? 11 : 9.5,
                              fontWeight: FontWeight.w600,
                              shadows: const [
                                Shadow(color: Colors.black, blurRadius: 3),
                              ],
                            ),
                          ),
                        ],
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
