"""앱이 쓰는 Open-Meteo 응답을 그대로 조회해 값·모델 지원 여부를 점검한다.

개발 샌드박스에서는 Open-Meteo가 막혀 있어, GitHub Actions 러너에서 돌린다
(`.github/workflows/probe-marine.yml`). 지점 예보의 바람·파고·너울이 다른
서비스와 어긋날 때, 원인이 **모델 미지원(폴백)**인지 **격자 해상도 차이**인지
구분하는 용도다.

실행: python3 tool/probe_marine.py [위도] [경도]
"""

import json
import sys
import urllib.request

MARINE = "https://marine-api.open-meteo.com/v1/marine"
FORECAST = "https://api.open-meteo.com/v1/forecast"

WAM_TOTAL = "wave_height,wave_period,wave_direction"
WAM_SWELL = "swell_wave_height,swell_wave_period,swell_wave_direction"


def get(url, params):
    q = "&".join(f"{k}={v}" for k, v in params.items())
    try:
        with urllib.request.urlopen(f"{url}?{q}", timeout=60) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")
    except Exception as e:  # noqa: BLE001
        return 0, {"error": str(e)}


def row(hourly, key, times):
    vals = hourly.get(key)
    if not vals:
        return "(없음)"
    t = hourly["time"]
    out = []
    for w in times:
        if w in t:
            v = vals[t.index(w)]
            out.append(f"{w[-5:-3]}시 {v}")
    return "  ".join(out)


def main():
    lat = sys.argv[1] if len(sys.argv) > 1 else "36.223"
    lon = sys.argv[2] if len(sys.argv) > 2 else "126.080"
    common = {
        "latitude": lat,
        "longitude": lon,
        "timezone": "Asia%2FSeoul",
        "forecast_days": "2",
    }
    print(f"== 지점 {lat}, {lon} ==\n")

    # 앞 6개 3시간 스텝을 뽑아 비교한다.
    st, base = get(MARINE, {**common, "hourly": WAM_TOTAL, "models": "ecmwf_wam025"})
    times = [t for t in base.get("hourly", {}).get("time", []) if t[11:13] in
             ("00", "03", "06", "09", "12", "15", "18", "21")][:8]

    print(f"[1] ECMWF WAM 총 파고  status={st}")
    if st == 200:
        for k in WAM_TOTAL.split(","):
            print(f"    {k:22s} {row(base['hourly'], k, times)}")

    st2, swell = get(MARINE, {**common, "hourly": WAM_SWELL, "models": "ecmwf_wam025"})
    print(f"\n[2] ECMWF WAM 너울    status={st2}  "
          f"{'지원함' if st2 == 200 else '미지원 → 앱은 GFS 너울로 폴백'}")
    if st2 == 200:
        for k in WAM_SWELL.split(","):
            print(f"    {k:26s} {row(swell['hourly'], k, times)}")
    else:
        print(f"    응답: {str(swell)[:200]}")

    st3, gfs = get(
        MARINE,
        {**common, "hourly": f"{WAM_TOTAL},{WAM_SWELL}", "models": "ncep_gfswave025"},
    )
    print(f"\n[3] GFS Wave (폴백원)  status={st3}")
    if st3 == 200:
        for k in ("wave_height", "swell_wave_height", "swell_wave_period"):
            print(f"    {k:26s} {row(gfs['hourly'], k, times)}")

    print("\n[4] 바람 모델별 비교 (풍속/돌풍 m/s)")
    for model in ("ecmwf_ifs025", "best_match", "kma_seamless", "icon_seamless"):
        stw, w = get(
            FORECAST,
            {
                **common,
                "hourly": "wind_speed_10m,wind_gusts_10m",
                "wind_speed_unit": "ms",
                "models": model,
            },
        )
        if stw != 200:
            print(f"    {model:16s} status={stw} (미지원)")
            continue
        h = w["hourly"]
        pairs = []
        for t in times:
            if t in h["time"]:
                i = h["time"].index(t)
                a, b = h["wind_speed_10m"][i], h["wind_gusts_10m"][i]
                pairs.append(f"{t[-5:-3]}시 {a}/{b}")
        print(f"    {model:16s} {'  '.join(pairs)}")


if __name__ == "__main__":
    main()
