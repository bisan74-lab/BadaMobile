"""바람 모델(ecmwf_ifs025 vs best_match)을 해역별로 비교한다.

지점 예보의 바람이 다른 서비스보다 낮게 나오는 문제를 두고, 모델을
바꿨을 때 **다도해(남해 연안 섬 사이)에서 지속풍이 낮아지는 부작용**이
실제로 있는지 수치로 확인하는 용도다. 개발 샌드박스에서는 Open-Meteo가
막혀 있어 GitHub Actions 러너에서 돌린다.

실행: python3 tool/probe_wind_models.py
"""

import json
import urllib.parse
import urllib.request

FORECAST = "https://api.open-meteo.com/v1/forecast"

# (해역구분, 지점명, 위도, 경도)
POINTS = [
    ("다도해 연안", "여수 가막만", 34.750, 127.700),
    ("다도해 연안", "여수 앞 수로", 34.600, 127.750),
    ("다도해 연안", "고흥 나로도", 34.470, 127.470),
    ("다도해 연안", "완도 앞", 34.300, 126.750),
    ("다도해 연안", "진도 울돌목 부근", 34.570, 126.300),
    ("다도해 연안", "신안 비금도 부근", 34.750, 126.050),
    ("남해 외해", "남해 먼바다", 33.500, 128.000),
    ("남해 외해", "거문도 남", 34.000, 127.300),
    ("남해 외해", "대한해협", 34.500, 129.200),
    ("서해", "외연도 근해", 36.223, 126.080),
    ("서해", "서해 먼바다", 35.500, 124.500),
    ("서해", "인천 앞바다", 37.350, 126.400),
    ("동해", "속초 앞바다", 38.200, 128.650),
    ("동해", "포항 앞바다", 36.050, 129.500),
    ("동해", "동해 먼바다", 37.000, 130.500),
]

MODELS = ("ecmwf_ifs025", "best_match")


def fetch(lat, lon, model):
    params = {
        "latitude": lat,
        "longitude": lon,
        "hourly": "wind_speed_10m,wind_gusts_10m",
        "wind_speed_unit": "ms",
        "timezone": "Asia/Seoul",
        "forecast_days": "2",
        "models": model,
    }
    url = f"{FORECAST}?{urllib.parse.urlencode(params)}"
    try:
        with urllib.request.urlopen(url, timeout=60) as r:
            h = json.loads(r.read().decode())["hourly"]
    except Exception as e:  # noqa: BLE001
        print(f"    ! {model} 조회 실패: {e}")
        return None, None
    ws = [v for v in h["wind_speed_10m"][:48] if v is not None]
    gs = [v for v in h["wind_gusts_10m"][:48] if v is not None]
    if not ws:
        return None, None
    return sum(ws) / len(ws), (sum(gs) / len(gs) if gs else None)


def main():
    print("48시간 평균 풍속/돌풍 (m/s) — ecmwf_ifs025(현재) vs best_match\n")
    header = f"{'해역':10s} {'지점':16s} {'IFS025':>14s} {'best_match':>14s} {'차이(풍속)':>12s}"
    print(header)
    print("-" * len(header))

    groups = {}
    for sea, name, lat, lon in POINTS:
        a_ws, a_gs = fetch(lat, lon, "ecmwf_ifs025")
        b_ws, b_gs = fetch(lat, lon, "best_match")
        if a_ws is None or b_ws is None:
            continue
        diff = b_ws - a_ws
        groups.setdefault(sea, []).append(diff)
        print(
            f"{sea:10s} {name:16s} "
            f"{a_ws:6.2f}/{a_gs or 0:5.2f} {b_ws:6.2f}/{b_gs or 0:5.2f} "
            f"{diff:+11.2f}"
        )

    print("\n해역별 평균 차이 (best_match − ecmwf_ifs025, 풍속 m/s)")
    print("  양수 = best_match가 더 강하게 봄 / 음수 = 더 약하게 봄")
    for sea, diffs in groups.items():
        avg = sum(diffs) / len(diffs)
        verdict = "더 강함" if avg > 0.2 else ("더 약함" if avg < -0.2 else "거의 같음")
        print(f"  {sea:12s} {avg:+6.2f}  ({verdict}, n={len(diffs)})")


if __name__ == "__main__":
    main()
