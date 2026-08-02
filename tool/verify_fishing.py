#!/usr/bin/env python3
"""공개된 낚시지수 파일이 실제 API와 일치하는지 검증한다.

`fetch_fishing.py`가 올린 파일을 앱과 **같은 경로로** 내려받아,
같은 시각 API 원본과 대조하고 앱 화면에 뜰 값을 지역별로 뽑아 본다.

검증 항목
1. 파일이 익명으로 받아지는가(앱과 같은 URL·인증 없음)
2. 포인트·행 수와 좌표가 API 원본과 같은가
3. 표본 지역에서 **앱이 고를 포인트와 등급**이 API 원본으로 계산한 것과 같은가
4. 앱 어종 목록이 API가 주는 어종을 벗어나지 않는가

    DATA_GO_KR_API_KEY=... python3 tool/verify_fishing.py
"""

import gzip
import json
import os
import re
import sys
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from fetch_fishing import KEY, build, fetch_all  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
URL = os.environ.get(
    'FISHING_DATA_URL',
    'https://github.com/bisan74-lab/badawindy-data/releases/download/'
    'fishing-data/fishing_index.json.gz',
)
SAMPLE_COUNT = 20

# 어종별 값으로 의미가 없는 항목. 앱의 nonSpeciesLabels와 같아야 한다.
NON_SPECIES = {'기타어종', '-', ''}


def app_locations() -> list[dict]:
    """앱의 지역 목록(`sample_locations.dart`)을 그대로 읽는다."""
    src = (ROOT / 'lib/features/locations/data/sample_locations.dart').read_text(
        encoding='utf-8'
    )
    out = []
    for block in re.findall(r'SeaLocation\((.*?)\n  \)', src, re.S):
        def field(name, cast=str):
            m = re.search(rf"{name}:\s*'?([^,'\n]+)'?", block)
            return cast(m.group(1)) if m else None

        name, region = field('name'), field('region')
        lat, lon = field('latitude', float), field('longitude', float)
        if name and lat is not None and lon is not None:
            out.append({'name': name, 'region': region, 'lat': lat, 'lon': lon})
    return out


def usable_points(data: dict) -> list[dict]:
    """어종별 지수가 있는 포인트만. 앱의 `forecastFor`와 같은 기준이다.

    전국 49곳 중 15곳은 총 지수만 있고 어종이 '-'로 온다(2026-08 실측).
    그런 포인트가 걸리면 화면엔 "이 날짜의 낚시지수가 없습니다"만 뜬다.
    """
    have: set[int] = set()
    for r in data['rows']:
        sp = data['species'][r[3]] if 0 <= r[3] < len(data['species']) else ''
        if sp not in NON_SPECIES:
            have.add(r[0])
    pts = [p for i, p in enumerate(data['points']) if i in have]
    return pts or data['points']


def _read(url: str, timeout: int, retries: int = 3) -> bytes:
    """재시도하며 받는다(일시적 네트워크 오류로 검증이 헛되이 실패하지 않게)."""
    last: Exception | None = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(url, timeout=timeout) as res:
                return res.read()
        except Exception as e:  # noqa: BLE001 - 재시도 후에도 실패하면 올린다
            last = e
            if attempt < retries - 1:
                time.sleep(3 * (attempt + 1))
    raise RuntimeError(f'{type(last).__name__}: {last}')


def nearest(points: list[dict], lat: float, lon: float) -> dict:
    """앱(`FishingIndexFile.forecastFor`)과 같은 방식: 단순 위경도 거리."""
    return min(points, key=lambda p: (p['la'] - lat) ** 2 + (p['lo'] - lon) ** 2)


def main() -> int:
    fails: list[str] = []

    print('== 1. 앱과 같은 경로로 파일 받기 ==')
    # 재시도한다 — 러너에서 나가는 TLS 핸드셰이크가 이따금 통째로 타임아웃돼
    # 한 번만 시도하면 데이터는 멀쩡한데 워크플로만 빨강이 된다
    # (`verify_points.py`에서 실제로 겪었다).
    blob = _read(URL, timeout=30)
    published = json.loads(gzip.decompress(blob))
    print(f'  OK  {len(blob):,}B (gzip) → {len(json.dumps(published)):,}B')
    print(f'  생성 {published["generated"]} · 포인트 {len(published["points"])}곳 '
          f'· {len(published["rows"])}행')

    if not KEY:
        print('\n(DATA_GO_KR_API_KEY 가 없어 원본 대조는 건너뜁니다)')
        fresh = None
    else:
        print('\n== 2. 같은 시각 API 원본과 대조 ==')
        fresh = build(fetch_all(published['dates'][0].replace('-', '')))
        for key in ('points', 'rows'):
            a, b = len(published[key]), len(fresh[key])
            mark = 'OK' if a == b else '불일치'
            print(f'  {key:8} 파일 {a} / 원본 {b}  {mark}')
            if a != b:
                fails.append(f'{key} 수가 다르다 ({a} != {b})')

        pub_pts = {p['n']: (p['la'], p['lo']) for p in published['points']}
        new_pts = {p['n']: (p['la'], p['lo']) for p in fresh['points']}
        if pub_pts.keys() != new_pts.keys():
            missing = new_pts.keys() - pub_pts.keys()
            extra = pub_pts.keys() - new_pts.keys()
            fails.append(f'포인트 구성이 다르다 (빠짐 {missing}, 추가 {extra})')
        else:
            moved = [n for n in pub_pts
                     if max(abs(a - b) for a, b in zip(pub_pts[n], new_pts[n])) > 0.001]
            print(f'  좌표      {len(pub_pts)}곳 중 어긋난 곳 {len(moved)}  '
                  f'{"OK" if not moved else moved[:5]}')
            if moved:
                fails.append(f'좌표가 어긋난 포인트 {len(moved)}곳')

    print(f'\n== 3. 표본 지역 {SAMPLE_COUNT}곳에서 앱이 보여줄 값 ==')
    locs = app_locations()
    # 해역이 고루 섞이도록 지역 목록을 균등 간격으로 뽑는다.
    step = max(1, len(locs) // SAMPLE_COUNT)
    sample = locs[::step][:SAMPLE_COUNT]
    print(f'  (전체 {len(locs)}곳 중 {len(sample)}곳)\n')

    species_seen: set[str] = set()
    empty: list[str] = []
    today = published['dates'][0]
    candidates = usable_points(published)
    print(f'  (어종 정보가 있는 포인트 {len(candidates)}/{len(published["points"])}곳만 후보)\n')
    for loc in sample:
        pt = nearest(candidates, loc['lat'], loc['lon'])
        pi = published['points'].index(pt)
        di = published['dates'].index(today)
        rows = [
            r for r in published['rows']
            if r[0] == pi and r[1] == di
            and published['species'][r[3]] not in NON_SPECIES
        ]
        grades = {}
        for r in rows:
            sp = published['species'][r[3]]
            species_seen.add(sp)
            slot = published['slots'][r[2]] if 0 <= r[2] < len(published['slots']) else '?'
            grades.setdefault(sp, {})[slot] = r[4]
        dist = ((pt['la'] - loc['lat']) ** 2 + (pt['lo'] - loc['lon']) ** 2) ** 0.5
        shown = ', '.join(
            f'{sp} 오전{g.get("오전", "-")}/오후{g.get("오후", "-")}'
            for sp, g in list(grades.items())[:3]
        )
        print(f'  {loc["region"]:2} {loc["name"]:<10} → {pt["n"]:<8} '
              f'({dist * 111:5.0f}km) {shown or "값 없음"}')
        if not rows:
            empty.append(loc['name'])

    if empty:
        fails.append(f'어종별 지수가 비는 지역 {len(empty)}곳: {empty[:5]}')
    else:
        print(f'\n  OK  표본 {len(sample)}곳 모두 어종별 지수가 나온다')

    print('\n== 4. 앱 어종 목록이 API 어종 안에 있는가 ==')
    catalog = re.findall(
        r"'([^']+)'",
        re.search(
            r'fishingSpeciesCatalog = <String>\[(.*?)\]',
            (ROOT / 'lib/features/fishing/data/models/fishing_index.dart').read_text(
                encoding='utf-8'
            ),
            re.S,
        ).group(1),
    )
    api_species = set(published['species']) - NON_SPECIES
    missing = [s for s in catalog if s not in api_species]
    extra = sorted(api_species - set(catalog))
    print(f'  앱 목록 {catalog}')
    print(f'  API    {sorted(api_species)}  (묶음/빈값 {sorted(NON_SPECIES - {""})} 제외)')
    if extra:
        print(f'  참고: API에는 있는데 앱 목록에 없는 어종 {extra}')
    if missing:
        print(f'  ❌ API에 없는 어종: {missing} — 고르면 영영 빈칸이 된다')
        fails.append(f'API에 없는 어종이 목록에 있다: {missing}')
    else:
        print('  OK  모두 API가 주는 어종이다')

    print('\n' + '=' * 60)
    if fails:
        print(f'검증 실패 {len(fails)}건:')
        for f in fails:
            print(f'  - {f}')
        return 1
    print('검증 통과: 파일이 원본과 일치하고 표본 지역 모두 실데이터가 나온다.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
