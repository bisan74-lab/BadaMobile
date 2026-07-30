#!/usr/bin/env python3
"""사용자가 제공한 지방어항현황·어촌정주어항현황·포구현황 CSV 5종
(tool/data_eohang/*.csv, 해양수산부 공공데이터)을 취합해
lib/features/locations/data/local_fishing_ports.dart를 생성한다.

소스별 좌표 신뢰도 우선순위(같은 항구가 여러 자료에 나오면 앞쪽 채택):
  B(현장 실측 GPS) > F(포구현황, 직접 위경도) > A(지방어항현황, POINT)
  > D(어촌정주어항 상세, TM좌표) > C(어촌정주어항 목록, D에 없는 것만).

TM좌표(어촌정주어항 C/D)는 EPSG:5179(UTM-K, 전국 통합좌표계)로 확인되어
pyproj로 위경도 변환한다. 이름이 같고 5km 이내 좌표는 같은 항구로
병합하고, 이름은 같아도 5km 넘게 떨어지면(동명이인) 시/군 또는 해역을
괄호로 붙여 구분한다. 기존 sample_locations 지점(curated + 국가어항)과
2km 이내로 겹치는 항구는 제외한다.

각 지점에 최근접 KHOA 조위관측소를 자동 매핑하되, 100km 넘게 떨어진
곳(백령도·울릉도 부속 항구)은 실측을 강제하지 않고 비워 둔다(합성 폴백).

실행: python3 tool/build_local_fishing_ports.py
(pyproj 필요: pip install pyproj)
"""

import csv
import math
import re
from collections import Counter, defaultdict

import pyproj

DATA_DIR = "tool/data_eohang"
OUT_PATH = "lib/features/locations/data/local_fishing_ports.dart"
EXISTING_LOCATIONS_PATH = "lib/features/locations/data/sample_locations.dart"
NATIONAL_PORTS_PATH = "lib/features/locations/data/national_fishing_ports.dart"

STATIONS = {
    "DT_0001": (37.452, 126.592), "DT_0002": (36.966, 126.823), "DT_0003": (35.373, 126.451),
    "DT_0004": (33.527, 126.543), "DT_0005": (35.090, 129.035), "DT_0006": (37.550, 129.115),
    "DT_0007": (34.780, 126.375), "DT_0008": (37.191, 126.649), "DT_0010": (33.240, 126.561),
    "DT_0011": (36.677, 129.453), "DT_0012": (38.207, 128.594), "DT_0014": (34.846, 128.433),
    "DT_0016": (34.747, 127.766), "DT_0017": (36.885, 126.312), "DT_0018": (35.975, 126.563),
    "DT_0020": (35.500, 129.417), "DT_0022": (33.458, 126.927), "DT_0023": (33.213, 126.251),
    "DT_0024": (36.005, 126.688), "DT_0025": (36.325, 126.508), "DT_0026": (34.481, 127.342),
    "DT_0027": (34.311, 126.755), "DT_0029": (34.878, 128.719), "DT_0035": (34.685, 125.435),
    "DT_0043": (37.245, 126.489), "DT_0051": (36.083, 126.560), "DT_0057": (37.494, 129.143),
    "DT_0061": (34.924, 128.069), "DT_0062": (35.196, 128.570), "DT_0067": (36.700, 126.135),
    "DT_0091": (36.047, 129.384),
}

SRC_PRIORITY = {"B": 0, "F": 1, "A": 2, "D": 3, "C": 4}


def dist_km(lat1, lon1, lat2, lon2):
    m = (lat1 + lat2) / 2 * math.pi / 180
    dx = (lon2 - lon1) * math.cos(m) * 111.32
    dy = (lat2 - lat1) * 111.32
    return math.sqrt(dx * dx + dy * dy)


def nearest_station(lat, lon):
    best_code, best_d = None, 1e9
    for code, (slat, slon) in STATIONS.items():
        d = dist_km(lat, lon, slat, slon)
        if d < best_d:
            best_d, best_code = d, code
    return best_code, best_d


def region_for(lat, lon):
    if lat < 34.15:
        return "제주"
    if 34.15 <= lat < 34.65 and lon < 127.9:
        return "남해"
    if lat >= 34.65 and lon < 126.85:
        return "서해"
    if lon >= 128.2:
        return "동해"
    return "남해"


def norm_name(n):
    return re.sub(r"\([^)]*\)", "", n).strip()


def gun_from_addr(addr):
    m = re.search(r"([가-힣]+(?:시|군|구))\s", addr or "")
    return m.group(1) if m else None


def parse_point(s):
    m = re.search(r"POINT\s*\(\s*([\d.]+)\s+([\d.]+)\s*\)", s or "")
    if not m:
        return None
    return float(m.group(2)), float(m.group(1))


def load_records(t5179):
    def parse_multipoint_tm(s):
        m = re.search(r"MULTIPOINT\s*\(\(\s*([\d.]+)\s+([\d.]+)\s*\)\)", s or "")
        if not m:
            return None
        x, y = float(m.group(1)), float(m.group(2))
        lon, lat = t5179.transform(x, y)
        return lat, lon

    records = []

    for r in csv.DictReader(open(f"{DATA_DIR}/local_ports_b_survey_gps.csv", encoding="utf-8")):
        lon_s, lat_s = r.get("경도", "").strip(), r.get("위도", "").strip()
        if not lon_s or not lat_s:
            continue
        try:
            lon, lat = float(lon_s), float(lat_s)
        except ValueError:
            continue
        if not (32 <= lat <= 39 and 124 <= lon <= 132):
            continue
        records.append({"name": r["어항명"].strip(), "lat": lat, "lon": lon, "source": "B", "addr": r.get("주소", "")})

    for r in csv.DictReader(open(f"{DATA_DIR}/local_ports_f_pogu.csv", encoding="utf-8")):
        try:
            lat, lon = float(r["위도"]), float(r["경도"])
        except ValueError:
            continue
        records.append({"name": r["어항명"].strip(), "lat": lat, "lon": lon, "source": "F", "addr": r.get("어항주소", "")})

    for r in csv.DictReader(open(f"{DATA_DIR}/local_ports_a_jibang.csv", encoding="utf-8")):
        p = parse_point(r.get("공간정보", ""))
        if not p:
            continue
        lat, lon = p
        records.append({"name": r["어항명"].strip(), "lat": lat, "lon": lon, "source": "A", "addr": r.get("항구지번주소", "")})

    for r in csv.DictReader(open(f"{DATA_DIR}/local_ports_d_eochon_detail.csv", encoding="utf-8")):
        p = parse_multipoint_tm(r.get("공간정보", ""))
        if not p:
            continue
        lat, lon = p
        records.append({"name": r["어촌정주어항명칭"].strip(), "lat": lat, "lon": lon, "source": "D", "addr": r.get("어촌정주어항주소", "")})

    d_names = {r["name"] for r in records if r["source"] == "D"}
    for r in csv.DictReader(open(f"{DATA_DIR}/local_ports_c_eochon_list.csv", encoding="utf-8")):
        name = r["어촌정주어항명칭"].strip()
        if name in d_names:
            continue
        p = parse_multipoint_tm(r.get("공간정보", ""))
        if not p:
            continue
        lat, lon = p
        records.append({"name": name, "lat": lat, "lon": lon, "source": "C", "addr": ""})

    return records


def load_existing_locations():
    existing = []
    for path in (EXISTING_LOCATIONS_PATH, NATIONAL_PORTS_PATH):
        src = open(path, encoding="utf-8").read()
        for b in re.findall(r"SeaLocation\(\s*(.*?)\n  \),", src, re.S):
            m_lat = re.search(r"latitude:\s*([\d.]+)", b)
            m_lon = re.search(r"longitude:\s*([\d.]+)", b)
            if "inland: true" in b or not m_lat or not m_lon:
                continue
            existing.append((float(m_lat.group(1)), float(m_lon.group(1))))
    return existing


def main():
    t5179 = pyproj.Transformer.from_crs("EPSG:5179", "EPSG:4326", always_xy=True)
    records = load_records(t5179)
    print(f"전체 레코드(중복 포함): {len(records)}")

    # 이름 기준 그룹화 후 5km 이내 좌표는 같은 항구로 클러스터링.
    groups = defaultdict(list)
    for r in records:
        groups[norm_name(r["name"])].append(r)

    clusters = []
    for name, recs in groups.items():
        recs = sorted(recs, key=lambda r: SRC_PRIORITY[r["source"]])
        used = [False] * len(recs)
        for i, r in enumerate(recs):
            if used[i]:
                continue
            cluster = [r]
            used[i] = True
            for j in range(i + 1, len(recs)):
                if not used[j] and dist_km(r["lat"], r["lon"], recs[j]["lat"], recs[j]["lon"]) <= 5.0:
                    cluster.append(recs[j])
                    used[j] = True
            clusters.append((name, cluster))

    merged = []
    for name, cluster in clusters:
        best = min(cluster, key=lambda r: SRC_PRIORITY[r["source"]])
        merged.append({"name": name, "lat": best["lat"], "lon": best["lon"], "addr": best.get("addr", "")})
    print(f"고유 클러스터(항구): {len(merged)}")

    # 기존 지점(curated + 국가어항)과 2km 이내 중복 제거.
    existing = load_existing_locations()
    kept = []
    for r in merged:
        d = min(dist_km(r["lat"], r["lon"], la, lo) for la, lo in existing)
        if d >= 2.0:
            kept.append(r)
    print(f"기존 지점과 겹치지 않는 순수 신규: {len(kept)}")

    # 동명이인(같은 base name, 다른 위치) 표시 구분.
    name_groups = defaultdict(list)
    for r in kept:
        name_groups[r["name"]].append(r)
    final = []
    for name, recs in name_groups.items():
        if len(recs) == 1:
            recs[0]["display_name"] = name
            final.extend(recs)
        else:
            for r in recs:
                gun = gun_from_addr(r.get("addr", ""))
                suffix = gun if gun else region_for(r["lat"], r["lon"])
                r["display_name"] = f"{name}({suffix})"
                final.append(r)

    for r in final:
        r["region"] = region_for(r["lat"], r["lon"])
        obs, d = nearest_station(r["lat"], r["lon"])
        r["obs"] = obs if d <= 100 else None

    # 접미사를 붙여도 남는 중복은 순번으로 최종 구분.
    c = Counter(r["display_name"] for r in final)
    seen = defaultdict(int)
    for r in final:
        if c[r["display_name"]] > 1:
            seen[r["display_name"]] += 1
            r["display_name"] = f"{r['display_name']}{seen[r['display_name']]}"

    print(f"최종 지점 수: {len(final)}")
    print(Counter(r["region"] for r in final))

    lines = [
        "import 'models/sea_location.dart';",
        "",
        "/// 지방어항현황·어촌정주어항현황·포구현황 등 해양수산부 공공데이터",
        "/// (5개 CSV, tool/data_eohang/, 사용자 제공)를 취합해 자동 추가한 지점.",
        "/// 생성 스크립트: tool/build_local_fishing_ports.py",
        "///",
        "/// 소스별 좌표 신뢰도 우선순위(같은 항구가 여러 자료에 나오면 앞쪽을",
        "/// 채택): ① 현장 실측 GPS 좌표 자료 ② 포구현황(직접 위경도)",
        "/// ③ 지방어항현황(POINT) ④ 어촌정주어항현황(TM좌표→위경도 변환,",
        "/// EPSG:5179 UTM-K). 이름+5km 이내 좌표는 같은 항구로 합쳤고, 이름은",
        "/// 같아도 5km 넘게 떨어지면(동명이인) 시/군 또는 해역을 괄호로 붙여",
        "/// 구분했다. 기존 지점(국가어항 등)과 2km 이내로 겹치는 항구는 제외.",
        "///",
        "/// 관측소는 최근접 KHOA 조위관측소를 자동 매핑했다(2차항 보정 없음 —",
        "/// national_fishing_ports.dart와 마찬가지로 실측 물때표 대조 전이라",
        "/// 오차가 있을 수 있다). 백령도·울릉도 부속 항구는 최근접 관측소가",
        "/// 100km+ 떨어져 있어 실측을 강제하지 않고 합성 폴백으로 둔다.",
        "/// rank 3(소규모)로 지도 우선순위를 낮춘다.",
        "const List<SeaLocation> localFishingPorts = [",
    ]
    for i, r in enumerate(final, 1):
        lines.append("  SeaLocation(")
        lines.append(f"    id: 'lp{i:04d}',")
        lines.append(f"    name: '{r['display_name'].replace(chr(39), chr(92) + chr(39))}',")
        lines.append(f"    region: '{r['region']}',")
        lines.append(f"    latitude: {round(r['lat'], 4)},")
        lines.append(f"    longitude: {round(r['lon'], 4)},")
        if r["obs"]:
            lines.append(f"    khoaStationCode: '{r['obs']}',")
        lines.append("    rank: 3,")
        lines.append("  ),")
    lines.append("];")
    lines.append("")

    open(OUT_PATH, "w", encoding="utf-8").write("\n".join(lines))
    print(f"작성 완료: {OUT_PATH}")


if __name__ == "__main__":
    main()
