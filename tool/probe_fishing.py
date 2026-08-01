#!/usr/bin/env python3
"""바다낚시지수 API가 실제로 얼마나 느린지 잰다.

앱이 지역을 바꿀 때마다 몇 초씩 멈추는 원인을 추측으로 고치지 않으려고,
앱과 **같은 요청**을 여러 번 보내 응답 시간·크기·건수를 기록한다.
`.github/workflows/probe-fishing.yml`이 Secret으로 키를 넣어 실행한다.

    DATA_GO_KR_API_KEY=... python3 tool/probe_fishing.py
"""

import gzip
import json
import os
import statistics
import sys
import time
import urllib.parse
import urllib.request

HOST = 'https://apis.data.go.kr/1192136/fcstFishingv2'
OP = 'GetFcstFishingApiServicev2'
KEY = os.environ.get('DATA_GO_KR_API_KEY', '')
TIMEOUT = 60

# 앱이 쓰는 것과 같은 필드만 남겼을 때의 크기를 같이 재려고 목록을 맞춰 둔다.
KEEP = {
    'seafsPstnNm', 'lat', 'lot',
    'predcYmd', 'predcNoonSeCd',
    'totalIndex', 'seafsTgfshNm',
    'tdlvHrCn',
    'minWvhgt', 'maxWvhgt', 'minWtem', 'maxWtem',
}


def fetch(ymd: str, rows: int, page: int = 1,
          gubun: str = '갯바위') -> tuple[float, int, bytes]:
    """(경과초, HTTP 상태, 본문)"""
    q = urllib.parse.urlencode({
        'serviceKey': KEY,
        'type': 'json',
        'reqDate': ymd,
        'gubun': gubun,
        'pageNo': str(page),
        'numOfRows': str(rows),
    })
    req = urllib.request.Request(f'{HOST}/{OP}?{q}')
    t0 = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
            body = res.read()
            return time.monotonic() - t0, res.status, body
    except Exception as e:  # noqa: BLE001 - 무슨 실패든 시간과 함께 남긴다
        return time.monotonic() - t0, -1, str(e).encode()


def items_of(body: bytes) -> list:
    doc = json.loads(body)
    doc = doc.get('response', doc)
    item = doc.get('body', {}).get('items', {}).get('item', [])
    return item if isinstance(item, list) else [item]


def main() -> int:
    if not KEY:
        print('::error::DATA_GO_KR_API_KEY 가 비어 있습니다.')
        return 1

    ymd = time.strftime('%Y%m%d')
    mode = os.environ.get('PROBE_MODE')
    if mode == 'limit':
        return probe_limit(ymd)
    if mode == 'gubun':
        return probe_gubun(ymd)
    print(f'조회 날짜 {ymd}\n')

    print('== 앱과 같은 요청(numOfRows=3000)을 5번 ==')
    times = []
    last = None
    for i in range(5):
        dt, status, body = fetch(ymd, 3000)
        times.append(dt)
        if status == 200:
            try:
                n = len(items_of(body))
            except Exception:
                n = -1
            print(f'  {i + 1}회  {dt:6.2f}초  {len(body):>9,}B  {n:>5}건')
            last = body
        else:
            print(f'  {i + 1}회  {dt:6.2f}초  실패: {body[:120].decode(errors="replace")}')
        time.sleep(1)

    if times:
        print(
            f'\n  최소 {min(times):.2f}초 / 중앙값 {statistics.median(times):.2f}초 '
            f'/ 최대 {max(times):.2f}초'
        )

    if last is None:
        print('\n::error::성공한 응답이 없습니다.')
        return 1

    items = items_of(last)
    slim = [{k: v for k, v in it.items() if k in KEEP} for it in items]
    raw_json = json.dumps(slim, ensure_ascii=False, separators=(',', ':'))
    gz = gzip.compress(raw_json.encode(), 9)

    print('\n== 크기 비교(앱이 매번 이만큼을 받아 파싱한다) ==')
    print(f'  원본 응답            {len(last):>9,}B')
    print(f'  쓰는 필드만 남기면   {len(raw_json.encode()):>9,}B')
    print(f'  그걸 gzip 하면       {len(gz):>9,}B  '
          f'({len(gz) / len(last) * 100:.1f}%)')

    if items:
        print(f'\n  첫 항목 필드 {len(items[0])}개: {", ".join(list(items[0])[:20])}')
        points = {it.get('seafsPstnNm') for it in items}
        species = {it.get('seafsTgfshNm') for it in items}
        dates = sorted({it.get('predcYmd') for it in items})
        print(f'  포인트 {len(points)}곳 · 어종 {len(species)}종 · 날짜 {dates}')

    print('\n== 페이지를 줄이면 빨라지는지(원인이 크기인지 확인) ==')
    for rows in (100, 500, 1000, 3000):
        dt, status, body = fetch(ymd, rows)
        mark = f'{len(body):,}B' if status == 200 else '실패'
        print(f'  numOfRows={rows:<5} {dt:6.2f}초  {mark}')
        time.sleep(1)

    return 0


def probe_limit(ymd: str) -> int:
    """numOfRows 상한을 찾고, 그 값으로 전 페이지를 받아 총 시간을 잰다."""
    print(f'조회 날짜 {ymd}\n')

    print('== numOfRows 상한 찾기 ==')
    best = 0
    for rows in (50, 100, 150, 200, 300, 500, 1000):
        dt, status, body = fetch(ymd, rows)
        try:
            n = len(items_of(body))
        except Exception:
            n = -1
        ok = n > 0
        if ok:
            best = max(best, rows)
        print(f'  numOfRows={rows:<5} {dt:5.2f}초  {len(body):>8,}B  {n:>4}건  '
              f'{"OK" if ok else "빈 응답"}')
        if not ok and len(body) < 400:
            print(f'      본문: {body.decode(errors="replace")[:300]}')
        time.sleep(1)

    if best == 0:
        print('\n::error::어떤 numOfRows로도 데이터를 받지 못했습니다.')
        return 1
    print(f'\n  → 쓸 수 있는 최대 numOfRows = {best}')

    print(f'\n== numOfRows={best}로 전 페이지 받기 ==')
    all_items, page, t0 = [], 1, time.monotonic()
    total = None
    while page <= 60:
        dt, status, body = fetch(ymd, best, page)
        if status != 200:
            print(f'  {page}쪽 실패: {body[:120].decode(errors="replace")}')
            break
        doc = json.loads(body)
        doc = doc.get('response', doc)
        if total is None:
            total = doc.get('body', {}).get('totalCount')
        got = items_of(body)
        print(f'  {page:>2}쪽 {dt:5.2f}초 {len(got):>4}건 (누적 {len(all_items) + len(got)})')
        all_items += got
        if not got or (total and len(all_items) >= int(total)):
            break
        page += 1
        time.sleep(0.2)

    elapsed = time.monotonic() - t0
    print(f'\n  총 {len(all_items)}건 / totalCount={total} / {elapsed:.1f}초 '
          f'({page}쪽)')

    if not all_items:
        return 1

    slim = [{k: v for k, v in it.items() if k in KEEP} for it in all_items]
    raw = json.dumps(slim, ensure_ascii=False, separators=(',', ':')).encode()
    gz = gzip.compress(raw, 9)
    points = {it.get('seafsPstnNm') for it in all_items}
    species = sorted({it.get('seafsTgfshNm') for it in all_items})
    dates = sorted({it.get('predcYmd') for it in all_items})

    print(f'\n  포인트 {len(points)}곳 · 어종 {len(species)}종 · 날짜 {dates}')
    print(f'  어종: {", ".join(str(s) for s in species)}')
    print('\n== 서버가 미리 받아 gz로 올릴 때의 크기 ==')
    print(f'  쓰는 필드만 남긴 JSON  {len(raw):>9,}B')
    print(f'  gzip                  {len(gz):>9,}B   '
          f'← 앱이 받을 양(지금은 {page}번 요청 {elapsed:.0f}초)')
    return 0


def probe_gubun(ymd: str) -> int:
    """구분(gubun)마다 어떤 어종·포인트가 오는지 본다.

    앱은 지금 '갯바위'만 받는다. 쭈꾸미·갑오징어·문어처럼 갯바위가 아닌
    낚시의 어종이 다른 구분에 있는지 확인하려는 것이다.
    """
    print(f'조회 날짜 {ymd}\n')
    candidates = [
        '갯바위', '방파제', '선상', '선상낚시', '백사장', '갯벌',
        '좌대', '선박', '방파제/좌대', '',
    ]
    for gubun in candidates:
        dt, status, body = fetch(ymd, 300, 1, gubun)
        label = gubun or '(빈값)'
        if status != 200:
            print(f'  {label:12} {dt:5.2f}초  요청 실패')
            time.sleep(1)
            continue
        try:
            items = items_of(body)
        except Exception as e:  # noqa: BLE001
            print(f'  {label:12} {dt:5.2f}초  파싱 실패 {e}')
            time.sleep(1)
            continue
        if not items:
            head = body[:120].decode(errors='replace')
            print(f'  {label:12} {dt:5.2f}초  0건  {head}')
            time.sleep(1)
            continue
        doc = json.loads(body)
        doc = doc.get('response', doc)
        total = doc.get('body', {}).get('totalCount')
        species = sorted({str(i.get('seafsTgfshNm')) for i in items})
        points = {str(i.get('seafsPstnNm')) for i in items}
        print(f'  {label:12} {dt:5.2f}초  totalCount={total} '
              f'포인트 {len(points)}곳')
        print(f'               어종: {", ".join(species)}')
        time.sleep(1)
    return 0


if __name__ == '__main__':
    sys.exit(main())
