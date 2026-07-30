"""육지/바다 판정용 폴리곤 데이터를 생성한다(작은 섬은 제외).

`lib/features/weather/data/land_polygons_data.dart`를 만든다. 지도에 그리는
해안선(`gen_coast.py`가 만드는 country_borders_data.dart)은 **열린 선(LineString)**
이라 point-in-polygon 판정에 쓸 수 없어서, 판정 전용으로 **닫힌 면(Polygon)**
데이터를 따로 뽑는다.

입력: Natural Earth 10m land (공개 도메인)
  https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/ne_10m_land.geojson

실행:
  python3 tool/gen_land.py ne_10m_land.geojson
"""

import json
import math
import sys

# 지도 bbox와 같은 범위(map_projection.dart의 mapViewBounds).
MINLAT, MAXLAT = 18.0, 57.0
MINLON, MAXLON = 108.0, 148.0

# RDP 단순화 허용 오차(도). 약 0.003° ≈ 330m — 연안에서 탭했을 때 육지/바다가
# 뒤집히지 않을 만큼은 촘촘하게 두되, 파일 크기가 과하지 않게 잡는다.
EPS = 0.003

# 이 넓이(제곱도)보다 작은 섬은 **일부러 넣지 않는다**. 이 데이터의 용도는
# "여기는 바다가 멀어서 파도 정보를 보여주면 안 되는 곳"을 가리는 것인데,
# 작은 섬은 어디를 찍어도 바다가 코앞이라 파도 정보가 오히려 필요하다
# (울릉도·위도·흑산도 같은 섬은 낚시 포인트 그 자체다).
# 0.05제곱도 ≈ 500km². 제주도(1848km²)는 남고, 거제·진도·강화도·울릉도는 빠진다.
MIN_LAND_AREA = 0.05


def clip(poly, edge):
    """Sutherland-Hodgman: 반평면 하나로 폴리곤을 자른다.

    [edge]는 (keep, axis, value) — axis 0=lon, 1=lat. keep이 'min'이면
    value 이상만, 'max'면 value 이하만 남긴다.
    """
    keep, axis, value = edge

    def is_in(p):
        return p[axis] >= value if keep == "min" else p[axis] <= value

    def intersect(a, b):
        # a→b 선분이 경계와 만나는 점.
        t = (value - a[axis]) / (b[axis] - a[axis])
        other = 1 - axis
        q = [0.0, 0.0]
        q[axis] = value
        q[other] = a[other] + (b[other] - a[other]) * t
        return (q[0], q[1])

    out = []
    n = len(poly)
    for i in range(n):
        cur, prev = poly[i], poly[i - 1]
        cur_in, prev_in = is_in(cur), is_in(prev)
        if cur_in:
            if not prev_in:
                out.append(intersect(prev, cur))
            out.append(cur)
        elif prev_in:
            out.append(intersect(prev, cur))
    return out


def clip_bbox(ring):
    """폴리곤 링을 bbox로 자른다. 결과가 없으면 빈 리스트."""
    poly = ring
    for edge in (
        ("min", 0, MINLON),
        ("max", 0, MAXLON),
        ("min", 1, MINLAT),
        ("max", 1, MAXLAT),
    ):
        if not poly:
            return []
        poly = clip(poly, edge)
    return poly


def perp(p, a, b):
    (px, py), (ax, ay), (bx, by) = p, a, b
    dx, dy = bx - ax, by - ay
    if dx == 0 and dy == 0:
        return math.hypot(px - ax, py - ay)
    t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def rdp(pts, eps):
    if len(pts) < 3:
        return pts
    dmax, idx = 0.0, 0
    for i in range(1, len(pts) - 1):
        d = perp(pts[i], pts[0], pts[-1])
        if d > dmax:
            dmax, idx = d, i
    if dmax <= eps:
        return [pts[0], pts[-1]]
    return rdp(pts[: idx + 1], eps)[:-1] + rdp(pts[idx:], eps)


def area(ring):
    """신발끈 공식(부호 없는 넓이, 제곱도)."""
    s = 0.0
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        s += x1 * y2 - x2 * y1
    return abs(s) / 2


def iter_rings(gj):
    """모든 폴리곤의 **바깥 링**만 돌려준다.

    안쪽 링(호수 등)은 일부러 무시한다 — 내륙 호수는 바다가 아니므로
    '육지'로 취급하는 편이 해양 예보 판정에 맞다.
    """
    for feat in gj["features"]:
        g = feat.get("geometry") or {}
        t, c = g.get("type"), g.get("coordinates")
        if t == "Polygon":
            yield c[0]
        elif t == "MultiPolygon":
            for part in c:
                yield part[0]


def main(paths):
    rings = []
    for path in paths:
        with open(path) as f:
            gj = json.load(f)
        for ring in iter_rings(gj):
            ring = [(float(x), float(y)) for x, y in ring]
            clipped = clip_bbox(ring)
            if len(clipped) < 3:
                continue
            simple = rdp(clipped, EPS)
            if len(simple) < 3 or area(simple) < MIN_LAND_AREA:
                continue
            rings.append(simple)

    rings.sort(key=area, reverse=True)
    total = sum(len(r) for r in rings)

    out = [
        "/// 육지/바다 판정 전용 폴리곤(Natural Earth 10m land, 공개 도메인).",
        "/// `tool/gen_land.py`가 자동 생성한다 — 직접 고치지 말 것.",
        "///",
        "/// 지도에 그리는 해안선(`country_borders_data.dart`)은 **열린 선**이라",
        "/// point-in-polygon에 쓸 수 없다. 이 파일은 그 판정만을 위한 **닫힌 면**이다.",
        "/// **작은 섬(500km\u00b2 미만)은 일부러 빠져 있다** — 섬은 어디를 찍어도",
        "/// 바다가 코앞이라 파도 정보를 그대로 보여주는 편이 맞기 때문이다.",
        "/// 넓은 땅부터 정렬돼 있어 대륙·큰 섬이 먼저 걸린다.",
        "library;",
        "",
        "const List<List<(double lat, double lon)>> landPolygons = [",
    ]
    for ring in rings:
        pts = ", ".join(f"({lat:.4f}, {lon:.4f})" for lon, lat in ring)
        out.append(f"  [{pts}],")
    out.append("];")

    dest = "lib/features/weather/data/land_polygons_data.dart"
    with open(dest, "w") as f:
        f.write("\n".join(out) + "\n")
    print(f"{dest}: 폴리곤 {len(rings)}개, 좌표 {total}개")


if __name__ == "__main__":
    main(sys.argv[1:])
