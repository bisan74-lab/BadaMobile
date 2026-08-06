#!/usr/bin/env python3
"""바다낚시지수 전국 하루치를 받아 앱이 쓸 작은 파일 하나로 만든다.

바람장(`fetch_wind.py`)과 같은 구조다. 서버가 하루 한 번 모아 두면 앱은
파일 하나만 내려받으면 된다.

**왜 서버로 옮기나**
data.go.kr의 이 API는 `numOfRows` 상한이 300이라 전국 1,750건을 받으려면
6쪽을 나눠 받아야 하고 6초쯤 걸린다(실측). 낚시지수는 하루 한 번 갱신되는
예보라 기기마다 이걸 반복할 이유가 없다. 서버가 한 번 모아 압축해 두면
앱은 20KB 남짓한 파일 하나(요청 1번)로 끝난다.

**상한을 넘기면 조용히 실패한다** — 500 이상을 넣으면 HTTP 200에
`resultCode: 10 INVALID_REQUEST_PARAMETER_ERROR`만 담긴 76B가 돌아온다.
예전 앱이 numOfRows=3000으로 요청해 늘 빈 응답을 받고 합성 데이터로
폴백하던 원인이었다. 이 값을 올릴 때는 반드시 실제 응답을 확인한다.

    DATA_GO_KR_API_KEY=... python3 tool/fetch_fishing.py
"""

import gzip
import json
import os
import sys
import time
import urllib.parse
import urllib.request

HOST = 'https://apis.data.go.kr/1192136/fcstFishingv2'
OP = 'GetFcstFishingApiServicev2'
KEY = os.environ.get('DATA_GO_KR_API_KEY', '')
OUT = os.environ.get('FISHING_OUT', 'fishing_index.json.gz')

# 이미 올라가 있는 파일(앱이 받는 것과 같은 주소). `--check-published`가 본다.
PUBLISHED_URL = os.environ.get(
    'FISHING_DATA_URL',
    'https://github.com/bisan74-lab/badawindy-data/releases/download/'
    'fishing-data/fishing_index.json.gz',
)

PAGE_ROWS = 300  # 실측 상한. 넘기면 INVALID_REQUEST_PARAMETER_ERROR.
MAX_PAGES = 40  # 안전장치(현재 6쪽이면 끝난다)

# 정상일 때 응답은 1~2초다. **60초를 기다린다는 건 이미 죽었다는 뜻**이라,
# 예전엔 3번 × 60초 = 3분을 통째로 날리고 실패했다(2026-08 실측). 짧게
# 끊고 대신 더 여러 번, 점점 길게 쉬면서 다시 물어본다.
TIMEOUT = 20
BACKOFF = [5, 15, 45, 120]  # 재시도 간격(초). 총 대기는 최대 약 3분 반.

# 기본 UA(`Python-urllib/3.x`)를 조용히 버리는 WAF가 흔하다 — 에러도 없이
# 타임아웃으로만 보인다. 사람이 쓰는 도구처럼 밝히고 부른다.
UA = 'BadaWindy-DataCollector/1.0 (+https://github.com/bisan74-lab/BadaMobile)'

SLOTS = ['오전', '오후']


class ApiError(RuntimeError):
    """서버가 제대로 답했는데 그 내용이 오류인 경우.

    파라미터가 틀렸다는 답은 몇 번을 다시 물어도 같으므로 **재시도하지
    않는다**(예전엔 이것도 3분씩 재시도했다).
    """


def _get(ymd: str, page: int) -> dict:
    q = urllib.parse.urlencode({
        'serviceKey': KEY,
        'type': 'json',
        'reqDate': ymd,
        'gubun': '갯바위',
        'pageNo': str(page),
        'numOfRows': str(PAGE_ROWS),
    })
    req = urllib.request.Request(
        f'{HOST}/{OP}?{q}', headers={'User-Agent': UA, 'Accept': '*/*'}
    )
    last = None
    for attempt in range(len(BACKOFF) + 1):
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
                doc = json.loads(res.read())
            doc = doc.get('response', doc)
            code = str(doc.get('header', {}).get('resultCode', ''))
            if code not in ('00', '0', ''):
                msg = doc.get('header', {}).get('resultMsg', '')
                raise ApiError(f'API 오류 {code} {msg}')
            return doc
        except ApiError:
            raise  # 다시 물어도 같은 답이다
        except Exception as e:  # noqa: BLE001 - 재시도 후에도 실패하면 그대로 올린다
            last = e
            if attempt < len(BACKOFF):
                wait = BACKOFF[attempt]
                print(f'  {page}쪽 {attempt + 1}번째 실패({e}) — {wait}초 뒤 재시도')
                time.sleep(wait)
    raise RuntimeError(f'{page}쪽 요청 실패: {last}')


def fetch_all(ymd: str) -> list[dict]:
    items: list[dict] = []
    total = None
    for page in range(1, MAX_PAGES + 1):
        doc = _get(ymd, page)
        body = doc.get('body', {})
        if total is None:
            total = int(body.get('totalCount') or 0)
        item = body.get('items', {}).get('item', [])
        got = item if isinstance(item, list) else [item]
        items += got
        print(f'  {page}쪽 {len(got)}건 (누적 {len(items)}/{total})')
        if not got or (total and len(items) >= total):
            break
        time.sleep(0.2)
    if total and len(items) != total:
        raise RuntimeError(f'건수 불일치: {len(items)} != totalCount {total}')
    return items


def _num(v):
    try:
        return round(float(v), 2)
    except (TypeError, ValueError):
        return None


def build(items: list[dict]) -> dict:
    """항목 목록을 색인 기반의 작은 구조로 바꾼다.

    같은 문자열(포인트명·어종·물때)이 수백 번 반복되므로 표로 빼고 번호만
    남긴다. 앱은 이 구조를 그대로 읽는다(`github_fishing_repository.dart`).
    """
    points: dict[str, tuple[float, float]] = {}
    species: list[str] = []
    dates: list[str] = []
    tides: list[str] = []
    rows: list[list] = []

    def idx(table: list[str], value: str) -> int:
        if value not in table:
            table.append(value)
        return table.index(value)

    for it in items:
        name = (it.get('seafsPstnNm') or '').strip()
        lat, lon = _num(it.get('lat')), _num(it.get('lot'))
        date = (it.get('predcYmd') or '').strip()
        grade = (it.get('totalIndex') or '').strip()
        if not name or lat is None or lon is None or not date or not grade:
            continue
        points.setdefault(name, (lat, lon))

        slot = (it.get('predcNoonSeCd') or '').strip()
        wave = [_num(it.get('minWvhgt')), _num(it.get('maxWvhgt'))]
        temp = [_num(it.get('minWtem')), _num(it.get('maxWtem'))]
        rows.append([
            list(points).index(name),
            idx(dates, date),
            SLOTS.index(slot) if slot in SLOTS else -1,
            idx(species, (it.get('seafsTgfshNm') or '').strip()),
            grade,
            _avg(wave),
            _avg(temp),
            idx(tides, (it.get('tdlvHrCn') or '').strip()),
        ])

    return {
        'fmt': 1,
        'generated': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        'points': [
            {'n': n, 'la': la, 'lo': lo} for n, (la, lo) in points.items()
        ],
        'dates': dates,
        'species': species,
        'tides': tides,
        'slots': SLOTS,
        # [포인트, 날짜, 오전/오후, 어종, 등급, 파고m, 수온C, 물때]
        'rows': rows,
    }


def _avg(pair):
    lo, hi = pair
    if lo is None:
        return hi
    if hi is None:
        return lo
    return round((lo + hi) / 2, 2)


def published_covers_today() -> bool:
    """이미 올라가 있는 파일이 **오늘 날짜를 담고 있는지** 본다.

    수집이 실패해도 그날 안에 다시 시도할 수 있게 크론을 여러 번 돌리는데,
    이미 성공한 날에는 data.go.kr을 또 두드릴 이유가 없다. 확인 자체가
    실패하면(파일 없음·네트워크 오류) **False**를 돌려 그냥 수집한다 —
    확인 때문에 수집을 건너뛰면 안 된다.
    """
    today = time.strftime('%Y%m%d')
    try:
        req = urllib.request.Request(
            PUBLISHED_URL, headers={'User-Agent': UA, 'Accept': '*/*'}
        )
        with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
            raw = res.read()
        data = json.loads(gzip.decompress(raw))
        # 파일의 날짜는 `2026-08-06` 형식이라 하이픈을 떼고 비교한다.
        return any(d.replace('-', '') == today for d in data.get('dates', []))
    except Exception as e:  # noqa: BLE001 - 확인 실패는 "없는 것"으로 친다
        print(f'  올라가 있는 파일 확인 실패({e}) — 그냥 수집한다')
        return False


def main() -> int:
    if '--check-published' in sys.argv:
        # 워크플로가 이 출력을 $GITHUB_OUTPUT으로 받아 수집 스텝을 건너뛴다.
        fresh = published_covers_today()
        print(f'fresh={"true" if fresh else "false"}')
        return 0

    if not KEY:
        print('::error::DATA_GO_KR_API_KEY 가 비어 있습니다.')
        return 1

    ymd = time.strftime('%Y%m%d')
    print(f'낚시지수 수집 {ymd} (쪽당 {PAGE_ROWS}건)')
    items = fetch_all(ymd)
    data = build(items)

    if not data['rows']:
        print('::error::쓸 수 있는 항목이 없습니다.')
        return 1

    raw = json.dumps(data, ensure_ascii=False, separators=(',', ':')).encode()
    with gzip.open(OUT, 'wb', compresslevel=9) as f:
        f.write(raw)

    size = os.path.getsize(OUT)
    print(
        f'완료: 포인트 {len(data["points"])}곳 · 어종 {len(data["species"])}종 · '
        f'날짜 {len(data["dates"])}일 · {len(data["rows"])}행'
    )
    print(f'      원본 {len(raw):,}B → gzip {size:,}B  ({OUT})')
    print(f'      어종: {", ".join(data["species"])}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
