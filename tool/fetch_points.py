#!/usr/bin/env python3
"""앱 지역별 대표 예보를 모아 작은 파일 하나로 만든다.

**왜 서버로 옮기나**
홈 화면과 낚시정보 카드는 지역마다 `OpenMeteoMarineRepository`를 호출하는데,
그 안에서 지역 하나당 요청이 **5번** 나간다(WAM 총파고 / WAM 너울 / GFS /
수온 / 육상예보). 그래서 새 지역을 고를 때마다 1~2초가 걸린다. 두 화면이
실제로 쓰는 건 **날짜별 대표값 하나씩**(바람·돌풍·풍향·파고·주기·수온·기온)뿐이라,
서버가 3시간 간격으로 모아 두면 앱은 파일 하나로 끝난다.

3시간 간격이면 대표값 선택 오차가 최대 1.5시간이다 — 이 화면들은 그 정도
신선도면 충분하다(지도 바람장은 별도로 1시간 간격 파일을 쓴다).

Open-Meteo는 좌표를 콤마로 이어 **여러 지점을 한 요청**으로 받을 수 있어서,
전국 68곳을 4번의 요청으로 끝낸다.

    python3 tool/fetch_points.py
"""

import gzip
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from app_locations import load as load_locations  # noqa: E402

MARINE_HOST = 'https://marine-api.open-meteo.com/v1/marine'
FORECAST_HOST = 'https://api.open-meteo.com/v1/forecast'
OUT = os.environ.get('POINTS_OUT', 'point_forecast.json.gz')

PAST_DAYS = 14  # 홈 화면이 과거 2주까지 날짜를 넘길 수 있다
FORECAST_DAYS = 16
STEP_HOURS = 3
TIMEOUT = 120
RETRIES = 3

# 앱 모델과 맞춘다 — 바람은 지도 바람장과 같은 ecmwf_ifs025, 파랑은 ECMWF WAM
# 우선에 GFS 폴백(`open_meteo_marine_repository.dart`와 같은 순서).
WIND_MODEL = 'ecmwf_ifs025'
WAVE_MODEL = 'ecmwf_wam025'
WAVE_FALLBACK_MODEL = 'ncep_gfswave025'

# 파일에 담는 값(순서 고정 — 앱의 parsePointForecastFile이 이 순서를 읽는다).
VARS = ['windMs', 'gustMs', 'dirDeg', 'waveM', 'periodS', 'sstC', 'airC']


def _get(url: str) -> list:
    last = None
    for attempt in range(RETRIES):
        try:
            with urllib.request.urlopen(url, timeout=TIMEOUT) as res:
                doc = json.loads(res.read())
            # 다지점 요청은 배열, 단일 지점은 객체로 온다.
            return doc if isinstance(doc, list) else [doc]
        except Exception as e:  # noqa: BLE001 - 재시도 후에도 실패하면 올린다
            last = e
            if attempt < RETRIES - 1:
                time.sleep(3 * (attempt + 1))
    raise RuntimeError(f'요청 실패: {last}\n{url[:160]}')


def _batch(host: str, locs: list[dict], hourly: str, model: str | None) -> list:
    params = {
        'latitude': ','.join(f'{loc["lat"]:.4f}' for loc in locs),
        'longitude': ','.join(f'{loc["lon"]:.4f}' for loc in locs),
        'hourly': hourly,
        'past_days': str(PAST_DAYS),
        'forecast_days': str(FORECAST_DAYS),
        'timezone': 'Asia/Seoul',
    }
    if model:
        params['models'] = model
    if host == FORECAST_HOST:
        params['wind_speed_unit'] = 'ms'
    docs = _get(f'{host}?{urllib.parse.urlencode(params)}')
    if len(docs) != len(locs):
        raise RuntimeError(f'응답 지점 수가 다르다: {len(docs)} != {len(locs)}')
    return docs


def _series(doc: dict, key: str) -> list:
    return (doc.get('hourly') or {}).get(key) or []


def _has_values(values: list) -> bool:
    return any(v is not None for v in values)


def main() -> int:
    locs = load_locations()
    print(f'지역 {len(locs)}곳 · 과거 {PAST_DAYS}일 + 예보 {FORECAST_DAYS}일 '
          f'· {STEP_HOURS}시간 간격')

    t0 = time.monotonic()
    wind = _batch(
        FORECAST_HOST, locs,
        'wind_speed_10m,wind_gusts_10m,wind_direction_10m,temperature_2m',
        WIND_MODEL,
    )
    wam = _batch(MARINE_HOST, locs, 'wave_height,wave_period', WAVE_MODEL)
    gfs = _batch(
        MARINE_HOST, locs, 'wave_height,wave_period', WAVE_FALLBACK_MODEL
    )
    sst = _batch(MARINE_HOST, locs, 'sea_surface_temperature', None)
    print(f'  요청 4번, {time.monotonic() - t0:.1f}초')

    times = _series(wind[0], 'time')
    if not times:
        print('::error::시간축이 비어 있습니다.')
        return 1
    # 시각은 지역마다 같다(같은 timezone·기간). 3시간 간격만 남긴다.
    keep = [i for i, t in enumerate(times) if int(t[11:13]) % STEP_HOURS == 0]
    kept_times = [times[i] for i in keep]

    series: list[list[list[float | None]]] = []
    wave_from_fallback = 0
    for n, loc in enumerate(locs):
        w, a, b, s = wind[n], wam[n], gfs[n], sst[n]
        # ECMWF WAM이 그 지점에서 전부 null이면 GFS 값을 쓴다(앱과 같은 순서).
        wave_src = a
        if not _has_values(_series(a, 'wave_height')):
            wave_src = b
            if _has_values(_series(b, 'wave_height')):
                wave_from_fallback += 1

        cols = {
            'windMs': _series(w, 'wind_speed_10m'),
            'gustMs': _series(w, 'wind_gusts_10m'),
            'dirDeg': _series(w, 'wind_direction_10m'),
            'waveM': _series(wave_src, 'wave_height'),
            'periodS': _series(wave_src, 'wave_period'),
            'sstC': _series(s, 'sea_surface_temperature'),
            'airC': _series(w, 'temperature_2m'),
        }
        series.append([
            [_round(cols[v][i] if i < len(cols[v]) else None, v) for i in keep]
            for v in VARS
        ])
        if (n + 1) % 20 == 0:
            print(f'  {n + 1}/{len(locs)}곳 정리')

    data = {
        'fmt': 1,
        'generated': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'stepHours': STEP_HOURS,
        'vars': VARS,
        'times': kept_times,
        'locations': [loc['id'] for loc in locs],
        # [지역][변수][시각] — 변수 순서는 vars와 같다.
        'series': series,
    }

    raw = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode()
    with gzip.open(OUT, 'wb', compresslevel=9) as f:
        f.write(raw)

    print(f'완료: {len(locs)}곳 × {len(kept_times)}스텝 × {len(VARS)}변수')
    print(f'      파랑을 GFS로 대체한 지역 {wave_from_fallback}곳')
    print(f'      원본 {len(raw):,}B → gzip {os.path.getsize(OUT):,}B  ({OUT})')
    print(f'      기간 {kept_times[0]} ~ {kept_times[-1]}')
    return 0


def _round(value, var: str):
    if value is None:
        return None
    # 자릿수를 줄이면 압축이 잘 된다. 화면 표시 정밀도(소수 1자리)면 충분하다.
    digits = 0 if var == 'dirDeg' else 1
    return round(float(value), digits)


if __name__ == '__main__':
    sys.exit(main())
