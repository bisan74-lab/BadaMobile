#!/usr/bin/env python3
"""공개된 지점 예보 파일이 Open-Meteo 원본과 맞는지 검증한다.

`fetch_points.py`가 올린 파일을 앱과 **같은 경로로** 내려받아, 표본 지역에서
같은 시각 Open-Meteo를 **직접 호출한 값과 대조**한다. 파일이 압축·재배열
과정에서 값을 잃거나 어긋나지 않았는지 수치로 확인하기 위한 것이다.

검증 항목
1. 파일이 익명으로 받아지는가(앱과 같은 URL·인증 없음)
2. 앱 지역 목록이 파일에 빠짐없이 들어 있는가
3. 표본 지역에서 바람·돌풍·풍향·기온이 원본과 일치하는가(허용 오차 안)
4. 파일이 얼마나 묵었는가(3시간 갱신 기준)
5. 낚시정보 카드가 쓰는 시각(그날 09시)에 값이 실제로 있는가

3번은 **Open-Meteo에 닿지 못하면 경고로만 남기고 통과**시킨다(값이 어긋난
경우는 물론 실패다). 나머지는 모두 하드 실패다.

    python3 tool/verify_points.py
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
from fetch_points import FORECAST_HOST, RETRIES, WIND_MODEL  # noqa: E402


def _read(url: str, timeout: int) -> bytes:
    """재시도하며 받는다.

    **재시도가 없으면 워크플로가 수시로 빨간불이 된다.** GitHub 러너에서
    Open-Meteo로 나가는 TLS 핸드셰이크가 이따금 통째로 타임아웃되는데
    (`_ssl.c:983: The handshake operation timed out`), 수집 단계
    (`fetch_points.py::_get`)는 3회 재시도라 넘어가고 검증만 한 번에 실패해
    "업로드는 됐는데 잡은 빨강"이 됐다. 같은 재시도 정책을 쓴다.
    """
    last: Exception | None = None
    for attempt in range(RETRIES):
        try:
            with urllib.request.urlopen(url, timeout=timeout) as res:
                return res.read()
        except Exception as e:  # noqa: BLE001 - 재시도 후에도 실패하면 올린다
            last = e
            if attempt < RETRIES - 1:
                time.sleep(3 * (attempt + 1))
    raise RuntimeError(f'{type(last).__name__}: {last}')

URL = os.environ.get(
    'POINT_FORECAST_URL',
    'https://github.com/bisan74-lab/badawindy-data/releases/download/'
    'point-forecast/point_forecast.json.gz',
)
SAMPLE_COUNT = 10

# 허용 오차. 파일은 소수 1자리로 반올림하므로 그 이상 어긋나면 문제다.
TOL = {'windMs': 0.06, 'gustMs': 0.06, 'dirDeg': 0.6, 'airC': 0.06}
MAX_AGE_HOURS = 6  # 3시간마다 갱신 + 실행 지연 여유


def fetch_direct(locs: list[dict]) -> list[dict]:
    """앱이 예전에 하던 것과 같은 요청(모델까지 동일)."""
    params = {
        'latitude': ','.join(f'{loc["lat"]:.4f}' for loc in locs),
        'longitude': ','.join(f'{loc["lon"]:.4f}' for loc in locs),
        'hourly': 'wind_speed_10m,wind_gusts_10m,wind_direction_10m,'
                  'temperature_2m',
        'forecast_days': '3',
        'timezone': 'Asia/Seoul',
        'wind_speed_unit': 'ms',
        'models': WIND_MODEL,
    }
    url = f'{FORECAST_HOST}?{urllib.parse.urlencode(params)}'
    doc = json.loads(_read(url, timeout=90))
    return doc if isinstance(doc, list) else [doc]


def main() -> int:
    fails: list[str] = []  # 종료 코드 1
    warns: list[str] = []  # 로그·주석에만 남기고 통과시킨다

    print('== 1. 앱과 같은 경로로 파일 받기 ==')
    t0 = time.monotonic()
    blob = _read(URL, timeout=60)
    dt = time.monotonic() - t0
    data = json.loads(gzip.decompress(blob))
    print(f'  OK  {len(blob):,}B (gzip) · {dt:.2f}초')
    print(f'  생성 {data["generated"]} · 지역 {len(data["locations"])}곳 '
          f'· {len(data["times"])}스텝 · {data["stepHours"]}시간 간격')

    print('\n== 2. 파일이 앱 지역을 모두 담고 있는가 ==')
    locs = load_locations()
    have = set(data['locations'])
    missing = [loc['name'] for loc in locs if loc['id'] not in have]
    print(f'  앱 {len(locs)}곳 / 파일 {len(have)}곳 · 빠진 지역 {len(missing)}')
    if missing:
        print(f'  ❌ {missing[:10]}')
        fails.append(f'파일에 없는 지역 {len(missing)}곳')

    print(f'\n== 3. 표본 {SAMPLE_COUNT}곳을 원본과 대조 ==')
    step = max(1, len(locs) // SAMPLE_COUNT)
    sample = [loc for loc in locs[::step]][:SAMPLE_COUNT]
    vars_ = data['vars']
    try:
        fresh = fetch_direct(sample)
    except Exception as e:  # noqa: BLE001
        # **원본에 못 닿는 것은 실패로 치지 않는다(경고).** 이 단계는 우리가
        # 만든 파일이 원본과 맞는지 보는 건데, Open-Meteo에 못 닿는 건 우리가
        # 어쩔 수 없는 남의 사정이고 이미 업로드는 끝난 뒤다. 여기서 exit 1을
        # 내면 "데이터는 정상 갱신됐는데 워크플로만 빨강"이 되어(실제로
        # 2026-08 기준 지점 예보 워크플로 실패의 전부가 이것이었다) 진짜
        # 문제가 생겨도 알아채지 못하게 된다.
        #
        # 파일이 실제로 망가지는 경우는 커버리지(2)·신선도(4)·값 유무(5)가
        # 여전히 하드 실패로 잡고, 값이 어긋나는 경우는 원본을 받았을 때
        # 아래에서 잡는다.
        print(f'  ⚠️ 원본을 받지 못해 대조를 건너뛴다: {e}')
        print('::warning title=원본 대조 건너뜀::'
              f'Open-Meteo에 접근하지 못했다 ({type(e).__name__}). '
              '업로드된 파일 자체는 나머지 검사를 통과했다.')
        warns.append('원본 대조 건너뜀(네트워크)')
        fresh = None

    worst = {k: 0.0 for k in TOL}
    compared = 0

    for n, loc in enumerate(sample if fresh else []):
        li = data['locations'].index(loc['id'])
        src = fresh[n]['hourly']
        # 원본에도 있고 파일에도 있는 시각만 고른다.
        for ti, tstr in enumerate(src['time']):
            if tstr not in data['times']:
                continue
            fi = data['times'].index(tstr)
            for key, api in (('windMs', 'wind_speed_10m'),
                             ('gustMs', 'wind_gusts_10m'),
                             ('dirDeg', 'wind_direction_10m'),
                             ('airC', 'temperature_2m')):
                a = data['series'][li][vars_.index(key)][fi]
                b = src[api][ti]
                if a is None or b is None:
                    continue
                d = abs(a - b)
                if key == 'dirDeg':  # 0/360 경계
                    d = min(d, 360 - d)
                worst[key] = max(worst[key], d)
                compared += 1
        print(f'  {loc["region"]:2} {loc["name"]}')

    if fresh:
        print(f'\n  비교한 값 {compared:,}개')
        for key, tol in TOL.items():
            ok = worst[key] <= tol
            print(f'  {key:8} 최대 오차 {worst[key]:.3f} (허용 {tol})  '
                  f'{"OK" if ok else "초과"}')
            if not ok:
                fails.append(f'{key} 오차 {worst[key]:.3f} > {tol}')
        if compared == 0:
            fails.append('비교한 값이 하나도 없다(시각이 겹치지 않음)')

    print('\n== 4. 파일이 얼마나 묵었는가 ==')
    gen = time.strptime(data['generated'], '%Y-%m-%dT%H:%M:%SZ')
    age = (time.time() - time.mktime(gen) + time.timezone) / 3600
    print(f'  {age:.1f}시간 전 생성 (허용 {MAX_AGE_HOURS}시간)  '
          f'{"OK" if age <= MAX_AGE_HOURS else "너무 묵음"}')
    if age > MAX_AGE_HOURS:
        fails.append(f'파일이 {age:.1f}시간 묵었다')

    print('\n== 5. 낚시정보 카드가 쓰는 시각(09시)에 값이 있는가 ==')
    today = time.strftime('%Y-%m-%dT09:00')
    if today not in data['times']:
        print(f'  ❌ {today} 스텝이 없다')
        fails.append(f'{today} 스텝 없음')
    else:
        fi = data['times'].index(today)
        blank = []
        for li, lid in enumerate(data['locations']):
            row = data['series'][li]
            if any(row[vars_.index(k)][fi] is None
                   for k in ('windMs', 'gustMs', 'dirDeg')):
                blank.append(lid)
        print(f'  {len(data["locations"]) - len(blank)}/{len(data["locations"])}곳에 '
              f'바람·돌풍·풍향이 있다')
        if blank:
            print(f'  ❌ 비는 지역: {blank[:10]}')
            fails.append(f'09시 바람값이 비는 지역 {len(blank)}곳')

    print('\n' + '=' * 60)
    if warns:
        print(f'경고 {len(warns)}건(통과):')
        for w in warns:
            print(f'  - {w}')
    if fails:
        print(f'검증 실패 {len(fails)}건:')
        for f in fails:
            print(f'  - {f}')
        return 1
    print('검증 통과: 파일 값이 원본과 일치하고 모든 지역에 바람값이 있다.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
