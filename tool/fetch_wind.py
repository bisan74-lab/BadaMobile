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

# 총점(64×66=4224)은 그대로 두되, **적응형(비균일) 격자**로 바꿔 같은 예산
# 안에서 재배치한다: 대한해협·서해·남해 연안처럼 바람이 국지적으로 빠르게
# 변하는 핵심 해역(LAT/LON_FOCUS)은 더 촘촘히, 먼 바다·내륙 쪽은 더 성기게
# 뽑는다. 예전 균일 0.62° 격자는 핵심 해역도 먼 바다와 같은 간격이라 Windy
# (더 촘촘한 원본 모델 해상도)보다 줄기·소용돌이가 뭉개져 보였다 — 총점을
# 올리지 않고도(호출 한도 그대로) 핵심 해역 실효 해상도를 끌어올리는 방향.
# 격자는 각 축(lat/lon)별로 독립적인 비균일 좌표 배열(위 아래 순, `lats`/
# `lons`)이고 outer product(=텐서 격자)로 좌표를 만든다 — 인덱스 규칙
# (index = i*lonSteps+j)은 그대로다. 앱(WindField)은 이 실제 좌표 배열을
# 그대로 받아 보간하므로 균일/비균일 여부와 무관하게 정확하다.
LAT_STEPS = 64
LON_STEPS = 66

# 핵심 해역: 대한해협을 포함한 한반도 서·남·동해 연안 전체.
LAT_FOCUS = (32.0, 40.0)
LON_FOCUS = (122.0, 132.0)
# 핵심 해역 중심의 밀도가 먼 바다 기본 밀도의 약 (1+DENSITY_BOOST)배가 되게
# 한다(격자점 간격은 그 역수만큼 좁아진다).
DENSITY_BOOST = 2.5

FORECAST_DAYS = 16  # Open-Meteo/ECMWF 모델 상한(지도 스크러버 최대치).
# 시간 해상도. 앞 FINE_HOURS 시간은 1시간 간격으로 촘촘히 남기고, 그 뒤는
# STEP_HOURS 간격으로 솎아 파일 크기를 억제한다. 3시간 간격만 쓰면 "지금"이
# 최대 3시간 전 값이라 실시간처럼 안 보인다(사용자 요구로 앞 구간만 촘촘히).
# 앞 48시간 1시간 + 나머지 3시간이면 스텝 수가 128 → 176으로 약 1.4배만 는다.
STEP_HOURS = 3  # 먼 구간 간격(시간)
FINE_STEP_HOURS = 1  # 가까운 구간 간격(시간)
FINE_HOURS = 48  # 이 시간까지는 FINE_STEP_HOURS로 촘촘히 남긴다
MODEL = "ecmwf_ifs025"  # Windy 기본 레이어와 같은 ECMWF IFS 0.25°.

# 한 요청 좌표 수. 500이면 URL이 8KB를 넘어 414(URI Too Large)로 거부되므로
# 작게 잡는다(앱 직접호출도 100씩 배치). SLEEP과 함께 분당 600콜 한도도 지킨다:
# 150좌표 / (요청~1s + 20s) ≈ 430콜/분 < 600.
BATCH = 150
SLEEP = 20  # 배치 사이 대기(초).
TIMEOUT = 60


def _density_axis(lo, hi, n, focus_lo, focus_hi, boost):
    """[lo,hi] 구간을 n개 점으로 나누되, (focus_lo,focus_hi) 근방에 밀도를
    더 준 비균일 오름차순 좌표를 만든다. 양 끝은 정확히 lo, hi로 고정된다.

    구현: 가우시안 밀도 가중치의 누적분포(CDF)를 촘촘한 균일 메시로 근사한
    뒤, CDF를 n등분한 분위점을 역보간(inverse-CDF sampling)해 좌표로 쓴다.
    """
    if n <= 1:
        return [lo]
    mesh_n = 2000
    xs = [lo + i * (hi - lo) / (mesh_n - 1) for i in range(mesh_n)]
    center = (focus_lo + focus_hi) / 2
    sigma = max((focus_hi - focus_lo) / 2.2, 1e-6)
    weights = [1.0 + boost * math.exp(-(((x - center) / sigma) ** 2)) for x in xs]
    cdf = [0.0] * mesh_n
    for i in range(1, mesh_n):
        cdf[i] = cdf[i - 1] + (weights[i] + weights[i - 1]) / 2 * (xs[i] - xs[i - 1])
    total = cdf[-1]
    cdf = [c / total for c in cdf]

    result = []
    for k in range(n):
        target = k / (n - 1)
        lo_i, hi_i = 0, mesh_n - 1
        while hi_i - lo_i > 1:
            mid = (lo_i + hi_i) // 2
            if cdf[mid] <= target:
                lo_i = mid
            else:
                hi_i = mid
        c0, c1 = cdf[lo_i], cdf[hi_i]
        x0, x1 = xs[lo_i], xs[hi_i]
        t = 0.0 if c1 == c0 else (target - c0) / (c1 - c0)
        result.append(x0 + t * (x1 - x0))
    result[0] = lo
    result[-1] = hi
    return result


def grid():
    lat_axis = _density_axis(MIN_LAT, MAX_LAT, LAT_STEPS, *LAT_FOCUS, DENSITY_BOOST)
    lon_axis = _density_axis(MIN_LON, MAX_LON, LON_STEPS, *LON_FOCUS, DENSITY_BOOST)
    lats, lons = [], []
    for lat in lat_axis:
        for lon in lon_axis:
            lats.append(round(lat, 3))
            lons.append(round(lon, 3))
    return lats, lons, lat_axis, lon_axis


def fetch_batch(lats, lons):
    params = {
        # 소수 2자리로 URL을 줄인다(격자 간격 약 0.62°라 0.01° 정밀도로 충분).
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
    lats, lons, lat_axis, lon_axis = grid()
    total = len(lats)
    print(
        f"격자 {LAT_STEPS}x{LON_STEPS} = {total}점(적응형, 핵심해역 밀도 "
        f"x{1 + DENSITY_BOOST:.1f}), {FORECAST_DAYS}일 요청",
        flush=True,
    )

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

    # 시간축: 첫 지점 기준. 앞 FINE_HOURS는 1시간, 그 뒤는 STEP_HOURS 간격.
    h0 = results[0].get("hourly") or {}
    all_times = h0.get("time") or []
    if not all_times:
        raise SystemExit("응답에 시간 데이터가 없습니다.")
    # 응답의 hourly는 1시간 간격이므로 인덱스가 곧 시작 기준 경과 시간이다.
    sel = [
        i
        for i, t in enumerate(all_times)
        if (i < FINE_HOURS and i % FINE_STEP_HOURS == 0)
        or (i >= FINE_HOURS and _hour_of(t) % STEP_HOURS == 0)
    ]

    # 요청한 기간(forecast_days) 전체를 스텝으로 남긴다 — 최신·최장 실데이터를
    # 우선한다(자르지 않음). 다만 모델(ecmwf_ifs025)이 실제로 예보하지 않는
    # 시각(대개 마지막 하루)은 Open-Meteo가 null을 주는데, 그대로 두면 우리가
    # 0으로 저장해 '무풍(전부 보라색)'과 '데이터 없음'이 구분이 안 된다.
    # 그래서 스텝별로 "어떤 지점이라도 값이 있었는지"를 valid 배열에 남겨
    # 앱이 데이터 없는 스텝을 회색으로 구분해 그릴 수 있게 한다.
    def _step_has_data(hi):
        for r in results:
            sp = (r.get("hourly") or {}).get("wind_speed_10m") or []
            if hi < len(sp) and sp[hi] is not None:
                return True
        return False

    steps = len(sel)
    start_time = all_times[sel[0]]
    valid = [1 if _step_has_data(hi) else 0 for hi in sel]
    n_invalid = valid.count(0)
    print(
        f"총 {steps}스텝, 실데이터 없는 꼬리 스텝 {n_invalid}개(회색 처리용 표시만, 삭제 안 함)",
        flush=True,
    )

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
        # fmt 3: 시간축도 비균일(앞 구간 1시간·뒤 3시간)이라 stepOffsets를
        # 추가로 담는다. fmt 2는 공간 격자만 비균일이었다. 구버전 앱도
        # 기존 필드가 그대로 있어 최소한 bbox·균일 간격으로는 동작한다.
        "fmt": 3,
        "generatedAt": _now_kst_iso(),
        "model": MODEL,
        "minLat": MIN_LAT,
        "maxLat": MAX_LAT,
        "minLon": MIN_LON,
        "maxLon": MAX_LON,
        "latSteps": LAT_STEPS,
        "lonSteps": LON_STEPS,
        "lats": [round(x, 3) for x in lat_axis],
        "lons": [round(x, 3) for x in lon_axis],
        "start": start_time,
        # 균일 간격 가정용(구버전 앱 폴백). 실제 간격은 아래 stepOffsets가 정확하다.
        "stepHours": STEP_HOURS,
        # fmt 3: 스텝이 균일 간격이 아니므로 start로부터의 경과 시간(시간 단위)을
        # 그대로 담는다. 앱은 이게 있으면 이걸 쓰고, 없으면 stepHours로 균일
        # 재구성한다(구버전 파일·캐시 호환).
        "stepOffsets": [hi - sel[0] for hi in sel],
        "steps": steps,
        # 스텝별로 모델의 실제 예보 범위 안인지(1) 아닌지(0). 없으면(예전
        # 포맷) 앱이 전부 유효한 것으로 취급한다.
        "valid": valid,
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
