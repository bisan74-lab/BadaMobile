import 'package:bada_mobile/features/weather/data/land_mask.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('바다는 바다로 판정한다', () {
    // 회귀 방지: 예전엔 열린 해안선(LineString)에 point-in-polygon을 돌려
    // 판정이 뒤집혔다. 서해 바다가 육지로 나와 파도 정보가 통째로 사라졌고
    // (사용자 스크린샷 2장), 반대로 서울은 바다로 나왔다.
    const seaPoints = <(String, double, double)>[
      ('보령 앞바다(사용자 스크린샷)', 36.240, 126.300),
      ('위도 서쪽 바다(사용자 스크린샷 부근)', 35.607, 126.150),
      ('황해 한복판', 36.000, 123.500),
      ('동해 앞바다', 35.500, 129.800),
      ('남해 먼바다', 33.500, 128.000),
      ('제주 남쪽 바다', 32.500, 126.500),
    ];

    for (final (name, lat, lon) in seaPoints) {
      test(name, () => expect(isOnLand(lat, lon), isFalse));
    }
  });

  group('바다가 먼 내륙은 육지로 판정한다', () {
    const landPoints = <(String, double, double)>[
      ('서울', 37.566, 126.978),
      ('대전', 36.350, 127.385),
      ('안동', 36.568, 128.730),
      ('광주', 35.160, 126.851),
      ('전주', 35.824, 127.148),
      ('삼척(폭 좁은 동해안)', 37.450, 129.150),
      ('제주도 내륙(한라산)', 33.380, 126.550),
    ];

    for (final (name, lat, lon) in landPoints) {
      test(name, () => expect(isOnLand(lat, lon), isTrue));
    }
  });

  group('작은 섬은 파도 정보를 살린다(육지로 막지 않는다)', () {
    // 섬은 어디를 찍어도 바다가 코앞이라 파도 정보가 오히려 필요하다.
    // gen_land.py가 500km² 미만 섬을 데이터에서 일부러 빼는 이유.
    const islandPoints = <(String, double, double)>[
      ('울릉도', 37.500, 130.865),
      ('위도', 35.617, 126.300),
      ('거제도', 34.880, 128.620),
    ];

    for (final (name, lat, lon) in islandPoints) {
      test(name, () => expect(isOnLand(lat, lon), isFalse));
    }
  });
}
