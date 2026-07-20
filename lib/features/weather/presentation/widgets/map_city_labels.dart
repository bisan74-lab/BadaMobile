import 'package:flutter/material.dart';

import 'map_projection.dart';

/// 지도 위 도시/지역 라벨. `rank`가 작을수록 낮은 배율(멀리서)에도 보인다 —
/// 지도 앱처럼 큰 도시부터 나타나고 확대할수록 더 많은 지역이 드러난다.
/// `island`이 true이면 바다 위 섬으로, 확대 시 물방울 모양 마커로 구분해 찍는다.
typedef CityLabel = ({
  String name,
  double lat,
  double lon,
  int rank,
  bool island,
});

const List<CityLabel> mapCityLabels = [
  // rank 1 — 특별시·광역시·주변국 대도시(기본 배율에서 항상 표시).
  (name: '서울', lat: 37.5665, lon: 126.9780, rank: 1, island: false),
  (name: '인천', lat: 37.4563, lon: 126.7052, rank: 1, island: false),
  (name: '부산', lat: 35.1796, lon: 129.0756, rank: 1, island: false),
  (name: '대구', lat: 35.8714, lon: 128.6014, rank: 2, island: false),
  (name: '대전', lat: 36.3504, lon: 127.3845, rank: 2, island: false),
  (name: '광주', lat: 35.1595, lon: 126.8526, rank: 2, island: false),
  (name: '울산', lat: 35.5384, lon: 129.3114, rank: 2, island: false),
  (name: '제주', lat: 33.4996, lon: 126.5312, rank: 1, island: true),
  (name: '강릉', lat: 37.7519, lon: 128.8761, rank: 2, island: false),
  (name: '평양', lat: 39.0392, lon: 125.7625, rank: 1, island: false),
  (name: '후쿠오카', lat: 33.5904, lon: 130.4017, rank: 1, island: false),

  // rank 2 — 도청소재지·중소도시(조금 확대하면 표시).
  (name: '수원', lat: 37.2636, lon: 127.0286, rank: 2, island: false),
  (name: '춘천', lat: 37.8813, lon: 127.7300, rank: 2, island: false),
  (name: '청주', lat: 36.6424, lon: 127.4890, rank: 2, island: false),
  (name: '전주', lat: 35.8242, lon: 127.1480, rank: 2, island: false),
  (name: '창원', lat: 35.2280, lon: 128.6811, rank: 2, island: false),
  (name: '포항', lat: 36.0190, lon: 129.3435, rank: 2, island: false),
  (name: '목포', lat: 34.8118, lon: 126.3922, rank: 2, island: false),
  (name: '여수', lat: 34.7604, lon: 127.6622, rank: 2, island: false),
  (name: '천안', lat: 36.8151, lon: 127.1139, rank: 2, island: false),
  (name: '원주', lat: 37.3422, lon: 127.9202, rank: 2, island: false),
  (name: '안동', lat: 36.5684, lon: 128.7294, rank: 2, island: false),
  (name: '세종', lat: 36.4800, lon: 127.2890, rank: 2, island: false),
  (name: '군산', lat: 35.9676, lon: 126.7369, rank: 2, island: false),
  (name: '통영', lat: 34.8544, lon: 128.4331, rank: 2, island: false),
  (name: '경주', lat: 35.8562, lon: 129.2247, rank: 2, island: false),
  (name: '속초', lat: 38.2070, lon: 128.5918, rank: 2, island: false),

  // rank 2 — 대표 섬(조금 확대하면 표시).
  (name: '강화도', lat: 37.7469, lon: 126.4880, rank: 2, island: true),
  (name: '거제도', lat: 34.8806, lon: 128.6211, rank: 2, island: true),
  (name: '울릉도', lat: 37.4843, lon: 130.9058, rank: 2, island: true),

  // rank 3 — 소도시·군(많이 확대해야 표시).
  (name: '서산', lat: 36.7848, lon: 126.4503, rank: 3, island: false),
  (name: '보령', lat: 36.3333, lon: 126.6127, rank: 3, island: false),
  (name: '태안', lat: 36.7456, lon: 126.2980, rank: 3, island: false),
  (name: '홍성', lat: 36.6013, lon: 126.6608, rank: 3, island: false),
  (name: '구미', lat: 36.1195, lon: 128.3446, rank: 3, island: false),
  (name: '순천', lat: 34.9506, lon: 127.4872, rank: 3, island: false),
  (name: '진주', lat: 35.1800, lon: 128.1076, rank: 3, island: false),
  (name: '영덕', lat: 36.4150, lon: 129.3656, rank: 3, island: false),
  (name: '울진', lat: 36.9930, lon: 129.4005, rank: 3, island: false),
  (name: '남해', lat: 34.8376, lon: 127.8925, rank: 3, island: false),
  (name: '고흥', lat: 34.6053, lon: 127.2850, rank: 3, island: false),
  (name: '부안', lat: 35.7317, lon: 126.7330, rank: 3, island: false),
  (name: '삼척', lat: 37.4497, lon: 129.1655, rank: 3, island: false),
  (name: '양양', lat: 38.0754, lon: 128.6190, rank: 3, island: false),

  // rank 3 — 바다 위 섬(많이 확대해야 표시).
  (name: '완도', lat: 34.3110, lon: 126.7550, rank: 3, island: true),
  (name: '진도', lat: 34.4867, lon: 126.2634, rank: 3, island: true),
  (name: '백령도', lat: 37.9636, lon: 124.6297, rank: 3, island: true),
  (name: '연평도', lat: 37.6636, lon: 125.7018, rank: 3, island: true),
  (name: '영흥도', lat: 37.2447, lon: 126.4869, rank: 3, island: true),
  (name: '안면도', lat: 36.5079, lon: 126.3339, rank: 3, island: true),
  (name: '흑산도', lat: 34.6839, lon: 125.4292, rank: 3, island: true),
  (name: '홍도', lat: 34.6857, lon: 125.1988, rank: 3, island: true),
  (name: '독도', lat: 37.2429, lon: 131.8686, rank: 3, island: true),

  // rank 3 — 낚시로 많이 가는 섬들(서해·남해 위주). 확대하면 드러난다.
  (name: '외연도', lat: 36.2072, lon: 126.0808, rank: 3, island: true),
  (name: '어청도', lat: 36.1156, lon: 125.9797, rank: 3, island: true),
  (name: '원산도', lat: 36.3606, lon: 126.4231, rank: 3, island: true),
  (name: '삽시도', lat: 36.2986, lon: 126.4136, rank: 3, island: true),
  (name: '녹도', lat: 36.3283, lon: 126.3178, rank: 3, island: true),
  (name: '호도', lat: 36.3222, lon: 126.2536, rank: 3, island: true),
  (name: '덕적도', lat: 37.2264, lon: 126.1394, rank: 3, island: true),
  (name: '굴업도', lat: 37.1922, lon: 125.9908, rank: 3, island: true),
  (name: '대이작도', lat: 37.2372, lon: 126.2286, rank: 3, island: true),
  (name: '위도', lat: 35.6208, lon: 126.3006, rank: 3, island: true),
  (name: '가의도', lat: 36.6803, lon: 126.1058, rank: 3, island: true),
  (name: '격렬비열도', lat: 36.5872, lon: 125.5528, rank: 3, island: true),
  (name: '거문도', lat: 34.0281, lon: 127.3122, rank: 3, island: true),
  (name: '청산도', lat: 34.1706, lon: 126.8556, rank: 3, island: true),
  (name: '보길도', lat: 34.1611, lon: 126.5306, rank: 3, island: true),
  (name: '추자도', lat: 33.9531, lon: 126.3011, rank: 3, island: true),
  (name: '가거도', lat: 34.0736, lon: 125.1214, rank: 3, island: true),
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

  /// rank·섬 여부별 시작 임계 배율. 기본 배율에서는 최상위 도시만 보이고,
  /// 확대할수록 더 많은 지역이 드러난다.
  static double _rankBase(CityLabel c) {
    if (c.island) {
      return switch (c.rank) {
        1 => 1.0,
        2 => 2.0,
        _ => 3.2,
      };
    }
    return switch (c.rank) {
      1 => 1.0,
      2 => 2.6,
      _ => 4.4,
    };
  }

  /// 같은 등급 안에서도 확대에 따라 라벨이 **한꺼번에가 아니라 하나씩** 늘어나게,
  /// 목록 순서(대략 중요도 순)대로 임계 배율을 조금씩 벌린 값(라벨별 캐시).
  static List<double>? _cached;
  static List<double> get _thresholds {
    final cached = _cached;
    if (cached != null) return cached;
    final seen = <String, int>{};
    final out = <double>[
      for (final c in mapCityLabels)
        () {
          final key = '${c.island}_${c.rank}';
          final n = seen[key] ?? 0;
          seen[key] = n + 1;
          return _rankBase(c) + n * 0.12;
        }(),
    ];
    _cached = out;
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final b = projection.bounds;
    final th = _thresholds;
    return Stack(
      children: [
        for (var i = 0; i < mapCityLabels.length; i++)
          if (scale >= th[i] &&
              mapCityLabels[i].lon >= b.minLon &&
              mapCityLabels[i].lon <= b.maxLon &&
              mapCityLabels[i].lat >= b.minLat &&
              mapCityLabels[i].lat <= b.maxLat)
            Builder(
              builder: (context) {
                final c = mapCityLabels[i];
                // 해안선과 같은 보정값을 적용해 지명이 육지 위에 얹히도록 한다.
                final o = projection.project(c.lat, c.lon + kMapLonShift);
                // 반도 안쪽(지도 중심)을 향해 글자를 배치한다: 뷰 중심 경도보다
                // 동쪽 지점이면 글자를 마커 왼쪽에 둬 동해안 지명이 바다로
                // 삐져나가지 않게 한다.
                final textLeft = c.lon > (b.minLon + b.maxLon) / 2 && !c.island;
                // 섬은 하늘색 마름모, 육지 도시는 흰 원으로 구분한다.
                final marker = c.island
                    ? Transform.rotate(
                        angle: 0.785398, // 45°
                        child: Container(
                          width: 3,
                          height: 3,
                          decoration: const BoxDecoration(
                            color: Color(0xFF9AD7FF),
                            boxShadow: [
                              BoxShadow(color: Colors.black54, blurRadius: 2),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        width: 3,
                        height: 3,
                        decoration: const BoxDecoration(
                          color: Color(0xFFCFD6DD),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Colors.black54, blurRadius: 2),
                          ],
                        ),
                      );
                final label = Text(
                  c.name,
                  style: TextStyle(
                    // 순백 대신 조금 어두운 회백색으로 덜 튀게.
                    color: c.island
                        ? const Color(0xFFA9C4D8)
                        : const Color(0xFFBCC5CE),
                    fontSize: c.rank == 1 ? 12.5 : 11,
                    fontWeight: FontWeight.w600,
                    shadows: const [Shadow(color: Colors.black, blurRadius: 3)],
                  ),
                );
                final row = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: textLeft
                      ? [label, const SizedBox(width: 3), marker]
                      : [marker, const SizedBox(width: 3), label],
                );
                return Positioned(
                  left: o.dx,
                  top: o.dy,
                  // 확대해도 지리 지점(o)에 마커가 고정되도록 topLeft를
                  // 피벗으로 역확대한다(기존 center 피벗은 배율에 따라 라벨이
                  // 동쪽으로 밀려 바다에 걸쳐 보이는 문제가 있었다).
                  child: Transform.scale(
                    scale: 1 / scale,
                    alignment: Alignment.topLeft,
                    child: FractionalTranslation(
                      // 세로는 항상 가운데, 가로는 마커가 o에 오도록 정렬.
                      // 글자를 왼쪽에 둘 땐 행 전체를 왼쪽으로 당겨 마커를 o에
                      // 붙인다.
                      translation: Offset(textLeft ? -1.0 : 0.0, -0.5),
                      child: row,
                    ),
                  ),
                );
              },
            ),
      ],
    );
  }
}
