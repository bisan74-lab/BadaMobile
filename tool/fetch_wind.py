#!/usr/bin/env python3
"""바람장 격자 데이터를 Open-Meteo에서 받아 앱이 읽을 gzip JSON으로 만든다.

서버(GitHub Actions 크론)에서 주기적으로 실행해 롤링 릴리스에 올리고, 앱은
그 정적 파일 하나만 내려받는다(features/weather/.../github_wind_field_repository.dart).
이렇게 하면:
- 사용자 기기가 Open-Meteo를 직접 다지점 호출하지 않아 분당 호출 한도에
  걸리지 않는다(모든 사용자가 같은 파일을 CDN에서 받음).
- 서버는 시간을 두고 배치로 나눠 받으므로 격자를 더 촘촘히(색 디테일↑) 뽑을
  수 있다.

Open-Meteo 무료 한도(분당 600콜, 다지점=좌표 1개=1콜)를 지키려고 좌표를
BATCH개씩 잘라 SLEEP초 간격으로 요청한다. GitHub 러너는 실행마다 IP가 달라
일일 한도는 사실상 매 실행 초기화된다.

출력 JSON(gzip): u/v를 cm/s 정밀도 int16로 양자화해 base64로 담는다.
격자 순서는 WindField와 동일하게 위도 오름차순(i) × 경도 오름차순(j),
index = i*lonSteps + j.
"""

import base64
import gzip
import json
import math
import sys
import time
import urllib.parse
import urllib.request

# 지도 뷰(map_projection.dart mapViewBounds) / 앱 격자와 같은 bbox.
MIN_LAT, MAX_LAT = 18.0, 57.0
MIN_LON, MAX_LON = 108.0, 148.0

# 약 1° 간격 — 앱 직접호출(504점, 약 2°)보다 3배 이상 촘촘해 색 변화가
# 윈디에 가깝게 세밀해진다. 서버는 배치로 나눠 받으므로 이 밀도가 가능하다.
LAT_STEPS = 40
LON_STEPS = 41

FORECAST_DAYS = 7
STEP_HOURS = 3  # 3시간 간격으로 솎아 파일 크기를 줄인다(지도 스크러버에 충분).
MODEL = "ecmwf_ifs025"  # Windy 기본 레이어와 같은 ECMWF IFS 0.25°.

# 한 요청 좌표 수. 500이면 URL이 8KB를 넘어 414(URI Too Large)로 거부되므로
# 작게 잡는다(앱 직접호출도 100씩 배치). SLEEP과 함께 분당 600콜 한도도 지킨다:
# 150좌표 / (요청~1s + 20s) ≈ 430콜/분 < 600.
BATCH = 150
SLEEP = 20  # 배치 사이 대기(초).
TIMEOUT = 60


def grid():
    lats, lons = [], []
    for i in range(LAT_STEPS):
        lat = MIN_LAT + i * (MAX_LAT - MIN_LAT) / (LAT_STEPS - 1)
        for j in range(LON_STEPS):
            lon = MIN_LON + j * (MAX_LON - MIN_LON) / (LON_STEPS - 1)
            lats.append(round(lat, 3))
            lons.append(round(lon, 3))
    return lats, lons


def fetch_batch(lats, lons):
    params = {
        # 소수 2자리로 URL을 줄인다(격자 간격 약 1°라 정밀도 충분).
        "latitude": ",".join(f"{v:.2f}" for v in lats),
        "longitude": ",".join(f"{v:.2f}" for v in lons),
        "hourly": "wind_speed_10m,wind_direction_10m",
        "wind_speed_unit": "ms",
        "timezone": "Asia/Seoul",
        "forecast_days": str(FORECAST_DAYS),
        "models": MODEL,
    }
    url = "https://api.open-meteo.com/v1/forecast?" + urllib.parse.urlencode(params)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=TIMEOUT) as r:
                data = json.loads(r.read())
                return data if isinstance(data, list) else [data]
        except Exception as e:  # noqa: BLE001
            wait = 30 * (attempt + 1)
            print(f"  batch 실패({e}); {wait}s 후 재시도", flush=True)
            time.sleep(wait)
    raise SystemExit("배치 요청이 반복 실패했습니다.")


def wind_to_uv(speed, direction):
    rad = math.radians(direction)
    return (-speed * math.sin(rad), -speed * math.cos(rad))


def main():
    lats, lons = grid()
    total = len(lats)
    print(f"격자 {LAT_STEPS}x{LON_STEPS} = {total}점, {FORECAST_DAYS}일 요청", flush=True)

    results = [None] * total
    for start in range(0, total, BATCH):
        end = min(start + BATCH, total)
        print(f"배치 {start}~{end}", flush=True)
        batch = fetch_batch(lats[start:end], lons[start:end])
        if len(batch) != end - start:
            raise SystemExit(f"배치 응답 개수 불일치: {len(batch)} != {end - start}")
        for k, obj in enumerate(batch):
            results[start + k] = obj
        if end < total:
            time.sleep(SLEEP)

    # 시간축: 첫 지점 기준, 3시간 간격으로 솎는다.
    h0 = results[0].get("hourly") or {}
    all_times = h0.get("time") or []
    if not all_times:
        raise SystemExit("응답에 시간 데이터가 없습니다.")
    sel = [i for i, t in enumerate(all_times) if _hour_of(t) % STEP_HOURS == 0]
    steps = len(sel)
    start_time = all_times[sel[0]]

    u16 = bytearray(steps * total * 2)
    v16 = bytearray(steps * total * 2)
    import struct

    for k in range(total):
        hourly = results[k].get("hourly") or {}
        speeds = hourly.get("wind_speed_10m") or []
        dirs = hourly.get("wind_direction_10m") or []
        for s, hi in enumerate(sel):
            sp = speeds[hi] if hi < len(speeds) and speeds[hi] is not None else 0.0
            di = dirs[hi] if hi < len(dirs) and dirs[hi] is not None else 0.0
            u, v = wind_to_uv(sp, di)
            pos = (s * total + k) * 2
            struct.pack_into("<h", u16, pos, _q(u))
            struct.pack_into("<h", v16, pos, _q(v))

    out = {
        "fmt": 1,
        "generatedAt": _now_kst_iso(),
        "model": MODEL,
        "minLat": MIN_LAT,
        "maxLat": MAX_LAT,
        "minLon": MIN_LON,
        "maxLon": MAX_LON,
        "latSteps": LAT_STEPS,
        "lonSteps": LON_STEPS,
        "start": start_time,
        "stepHours": STEP_HOURS,
        "steps": steps,
        "u": base64.b64encode(bytes(u16)).decode(),
        "v": base64.b64encode(bytes(v16)).decode(),
    }
    raw = json.dumps(out, separators=(",", ":")).encode()
    with gzip.open("wind_field.json.gz", "wb", compresslevel=9) as f:
        f.write(raw)
    print(
        f"완료: {steps}스텝 x {total}점, 원본 {len(raw)}B "
        f"(gzip 파일 생성)",
        flush=True,
    )


def _q(x):
    return max(-32000, min(32000, round(x * 100)))


def _hour_of(iso):
    # "2026-07-21T00:00" → 0
    return int(iso[11:13])


def _now_kst_iso():
    # 러너는 UTC이므로 +9시간해 서울 시각 표기.
    t = time.gmtime(time.time() + 9 * 3600)
    return time.strftime("%Y-%m-%dT%H:%M:%S+09:00", t)


if __name__ == "__main__":
    sys.exit(main())
