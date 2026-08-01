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


def fetch(ymd: str, rows: int) -> tuple[float, int, bytes]:
    """(경과초, HTTP 상태, 본문)"""
    q = urllib.parse.urlencode({
        'serviceKey': KEY,
        'type': 'json',
        'reqDate': ymd,
        'gubun': '갯바위',
        'pageNo': '1',
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


if __name__ == '__main__':
    sys.exit(main())
