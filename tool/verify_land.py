"""앱의 육지/바다 판정을 원본 고해상도 데이터와 대조해 자체 검증한다.

실행: python3 tool/verify_land.py ne_10m_land.geojson ne_10m_minor_islands.geojson
(numpy 필요. gen_land.py로 데이터를 다시 뽑은 뒤 이걸로 회귀를 확인한다.)

- 기준(ground truth): ne_10m_land.geojson 원본(단순화 전) + ne_10m_minor_islands
- 검사 대상: lib/features/weather/data/land_polygons_data.dart (앱이 실제로 쓰는 것)

서해·남해·동해를 격자로 훑어, 앱이 **바다를 육지로** 잘못 보는 지점(사용자가
겪은 버그)과 **육지를 바다로** 보는 지점을 각각 찾아낸다.
"""

import json
import re
import sys

import numpy as np

# Natural Earth 원본(단순화 전). gen_land.py 주석의 URL에서 받아 둔다.
LAND = sys.argv[1] if len(sys.argv) > 1 else "ne_10m_land.geojson"
ISLANDS = sys.argv[2] if len(sys.argv) > 2 else "ne_10m_minor_islands.geojson"
DART = "lib/features/weather/data/land_polygons_data.dart"

# 한반도 주변 검사 범위
LAT0, LAT1, LON0, LON1 = 32.5, 39.0, 123.5, 132.0
STEP = 0.02


def rings_from_geojson(path):
    with open(path) as f:
        gj = json.load(f)
    out = []
    for feat in gj["features"]:
        g = feat.get("geometry") or {}
        t, c = g.get("type"), g.get("coordinates")
        if t == "Polygon":
            out.append(c[0])
        elif t == "MultiPolygon":
            for part in c:
                out.append(part[0])
    return [np.asarray(r, dtype=float) for r in out if len(r) >= 3]


def rings_from_dart(path):
    """land_polygons_data.dart의 (lat, lon) 목록을 (lon, lat) 배열로 읽는다.

    dart format이 긴 리스트를 여러 줄로 쪼개므로 줄 단위가 아니라
    대괄호 깊이를 따라가며 최상위 링을 잘라낸다.
    """
    text = open(path).read()
    body = text.split("landPolygons = [", 1)[1]
    body = body[: body.rindex("];")]
    out, depth, start = [], 0, None
    for i, ch in enumerate(body):
        if ch == "[":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0 and start is not None:
                chunk = body[start : i + 1]
                nums = re.findall(r"\(\s*([-\d.]+),\s*([-\d.]+)\s*\)", chunk)
                if len(nums) >= 3:
                    out.append(np.asarray([(float(b), float(a)) for a, b in nums]))
                start = None
    return out


def inside_mask(rings, lons, lats):
    """격자점들이 폴리곤 안인지 벡터화 ray-casting으로 판정한다."""
    res = np.zeros(lons.shape, dtype=bool)
    for ring in rings:
        rx, ry = ring[:, 0], ring[:, 1]
        # 바운딩 박스로 후보를 먼저 좁힌다.
        cand = (
            (lons >= rx.min())
            & (lons <= rx.max())
            & (lats >= ry.min())
            & (lats <= ry.max())
        )
        if not cand.any():
            continue
        px, py = lons[cand], lats[cand]
        acc = np.zeros(px.shape, dtype=bool)
        x1, y1 = rx, ry
        x2, y2 = np.roll(rx, -1), np.roll(ry, -1)
        for i in range(len(rx)):
            cond = ((y1[i] > py) != (y2[i] > py)) & (
                px
                < (x2[i] - x1[i]) * (py - y1[i]) / (y2[i] - y1[i] + 1e-300) + x1[i]
            )
            acc ^= cond
        res[cand] |= acc
    return res


def main():
    lat_axis = np.arange(LAT0, LAT1, STEP)
    lon_axis = np.arange(LON0, LON1, STEP)
    LonG, LatG = np.meshgrid(lon_axis, lat_axis)
    lons, lats = LonG.ravel(), LatG.ravel()
    print(f"검사 격자: {len(lons):,}점 ({STEP}° 간격)")

    truth_big = inside_mask(rings_from_geojson(LAND), lons, lats)
    truth_small = inside_mask(rings_from_geojson(ISLANDS), lons, lats)
    truth = truth_big | truth_small
    app = inside_mask(rings_from_dart(DART), lons, lats)

    # 앱이 바다를 육지로 본 지점 = 사용자가 겪은 버그(파도 정보가 사라짐)
    false_land = app & ~truth
    # 앱이 육지를 바다로 본 지점(작은 섬은 의도한 동작)
    false_sea = truth & ~app
    false_sea_small_island = false_sea & truth_small & ~truth_big

    n = len(lons)
    print(f"실제 육지: {truth.sum():,} / 바다: {(~truth).sum():,}")
    print()
    print(f"[중요] 바다를 육지로 오판: {false_land.sum():,}점 "
          f"({100 * false_land.sum() / max(1, (~truth).sum()):.3f}% of 바다)")
    print(f"       육지를 바다로 판정: {false_sea.sum():,}점")
    print(f"        └ 그중 작은 섬(의도된 제외): {false_sea_small_island.sum():,}점")
    print(f"        └ 그 외(단순화 오차): "
          f"{(false_sea & ~false_sea_small_island).sum():,}점")

    if false_land.any():
        idx = np.where(false_land)[0]
        print("\n바다인데 육지로 본 지점 샘플(최대 25개):")
        for i in idx[:: max(1, len(idx) // 25)][:25]:
            print(f"  위도 {lats[i]:.3f}, 경도 {lons[i]:.3f}")

    # 해역별 요약
    print("\n해역별 '바다를 육지로 오판' 비율:")
    seas = {
        "서해(황해)": (lons < 126.5) & (lats > 34.0),
        "남해": (lats <= 34.6) & (lons >= 126.0) & (lons <= 129.5),
        "동해": (lons > 129.0) & (lats > 35.0),
    }
    for name, m in seas.items():
        sea_cells = m & ~truth
        bad = m & false_land
        if sea_cells.sum():
            print(f"  {name}: {bad.sum():,} / {sea_cells.sum():,} "
                  f"({100 * bad.sum() / sea_cells.sum():.3f}%)")
    return 0 if false_land.sum() == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
