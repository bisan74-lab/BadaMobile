#!/usr/bin/env python3
"""조위관측소 실측·예측 조위 API 디버그: 관측소별 만조/간조를 계산해 출력한다.

앱(DataGoKrTideObsRepository)과 동일한 방식(10분 시계열 → 국소 극값 → 이웃
3점 포물선 정밀화)으로 만조/간조를 뽑아, 실제 물때표(바다타임 등)와 관측소
원본 값을 직접 대조하기 위한 것이다. 지점 보정(시간차·조위비)을 캘리브레이션
할 때 정답지 확보용으로 GitHub Actions에서 실행한다(키는 Secret).
"""

import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta

KEY = os.environ.get("DATA_GO_KR_API_KEY", "")
if not KEY:
    sys.exit("DATA_GO_KR_API_KEY 환경변수가 없습니다.")

STATIONS = {
    "DT_0025": "보령(대천항)",
    "DT_0051": "서천마량",
    "DT_0026": "고흥발포",
    "DT_0027": "완도",
}

BASE = "https://apis.data.go.kr/1192136/surveyTideLevel/GetSurveyTideLevelApiService"


def fetch_day(obs, ymd):
    params = {
        "serviceKey": KEY,
        "type": "json",
        "obsCode": obs,
        "reqDate": ymd,
        "min": "10",
        "numOfRows": "300",
    }
    url = BASE + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=30) as r:
        body = json.loads(r.read())
    resp = body.get("response", body)
    header = resp.get("header") or {}
    code = str(header.get("resultCode", ""))
    if code not in ("0", "00"):
        print(f"  ! {obs} {ymd}: resultCode={code} {header.get('resultMsg')}")
        return []
    items = ((resp.get("body") or {}).get("items") or {}).get("item") or []
    if isinstance(items, dict):
        items = [items]
    out = []
    for it in items:
        t = it.get("obsrvnDt")
        lvl = it.get("tdlvHgt", it.get("bscTdlvHgt"))
        if t is None or lvl is None:
            continue
        out.append((datetime.fromisoformat(str(t).replace(" ", "T")), float(lvl)))
    return out


def extremes(series):
    """국소 극값 + 이웃 3점 포물선 정밀화(앱과 동일)."""
    out = []
    for i in range(1, len(series) - 1):
        (t0, y0), (t1, y1), (t2, y2) = series[i - 1], series[i], series[i + 1]
        is_high = y1 >= y0 and y1 > y2
        is_low = y1 <= y0 and y1 < y2
        if not (is_high or is_low):
            continue
        denom = y0 - 2 * y1 + y2
        d = 0.0 if denom == 0 else max(-0.5, min(0.5, 0.5 * (y0 - y2) / denom))
        half = (t2 - t0).total_seconds() / 2
        t = t1 + timedelta(seconds=d * half)
        h = y1 - 0.25 * (y0 - y2) * d
        out.append((t, h, is_high))
    return out


def main():
    dates = sys.argv[1:] or [datetime.now().strftime("%Y%m%d")]
    for obs, name in STATIONS.items():
        print(f"\n=== {obs} {name} ===")
        for ymd in dates:
            day = datetime.strptime(ymd, "%Y%m%d")
            series = []
            for d in (day - timedelta(days=1), day, day + timedelta(days=1)):
                series += fetch_day(obs, d.strftime("%Y%m%d"))
            series.sort(key=lambda x: x[0])
            dedup = []
            for s in series:
                if not dedup or dedup[-1][0] != s[0]:
                    dedup.append(s)
            if len(dedup) < 3:
                print(f"  {ymd}: 시계열 부족({len(dedup)}점)")
                continue
            print(f"  {ymd}: {len(dedup)}점")
            for t, h, is_high in extremes(dedup):
                if t.date() != day.date():
                    continue
                kind = "만조" if is_high else "간조"
                print(f"    {kind} {t:%H:%M} ({h:.0f})")


if __name__ == "__main__":
    main()
