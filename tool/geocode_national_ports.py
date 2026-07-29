#!/usr/bin/env python3
"""국가어항 목록(tool/data_gukga_eohang.csv, 해양수산부 공공데이터)의 주소를
OpenStreetMap Nominatim(무료·키 불필요)으로 지오코딩해 좌표를 얻는다.

이 세션(로컬 개발 환경)은 egress 정책상 badatime.com·nominatim 등 임의
외부 API에 직접 접근할 수 없어(카카오맵 place 페이지도 403), 네트워크
제한이 없는 GitHub Actions 러너에서 이 스크립트를 실행하고 결과를 로그의
JSON 한 줄로 받는다(tide-debug.yml과 같은 패턴).

Nominatim 사용 정책 준수: User-Agent 지정, 요청 간 1.1초 이상 간격.
도로명주소 그대로 → 실패 시 "항구명 항구, 구/군, 시도" → 실패 시
"시도 구/군"만으로 단계적으로 완화해 재시도한다.
"""

import csv
import json
import sys
import time
import urllib.parse
import urllib.request

NOMINATIM = "https://nominatim.openstreetmap.org/search"
UA = "BadaMobile-geocode/1.0 (contact: bisan74@gmail.com)"


def query(q):
    params = {"q": q, "format": "json", "limit": 1, "countrycodes": "kr"}
    url = NOMINATIM + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            body = json.loads(r.read())
    except Exception as e:
        print(f"    ! 오류: {e}", file=sys.stderr)
        return None
    if not body:
        return None
    return float(body[0]["lat"]), float(body[0]["lon"])


def split_addr(addr):
    """도로명주소에서 '시도 시군구' 접두어를 뽑는다(대략 2어절)."""
    parts = addr.split()
    return " ".join(parts[:2]) if len(parts) >= 2 else addr


def main():
    rows = []
    with open("tool/data_gukga_eohang.csv", encoding="utf-8") as f:
        r = csv.reader(f)
        next(r)
        for row in r:
            if len(row) >= 3 and row[0].strip():
                rows.append({"no": row[0], "name": row[1].strip(), "addr": row[2].strip()})

    print(f"총 {len(rows)}개 항구 지오코딩 시작", file=sys.stderr)
    results = []
    for i, row in enumerate(rows):
        name, addr = row["name"], row["addr"]
        region = split_addr(addr)
        candidates = [
            f"{addr}, South Korea",
            f"{name}, {region}, South Korea",
            f"{region}, South Korea",
        ]
        found = None
        for q in candidates:
            found = query(q)
            time.sleep(1.1)
            if found:
                break
        status = "ok" if found else "fail"
        print(f"  [{i+1}/{len(rows)}] {name} ({region}) -> {found} ({status})", file=sys.stderr)
        results.append(
            {
                "name": name,
                "addr": addr,
                "region_hint": region,
                "lat": found[0] if found else None,
                "lon": found[1] if found else None,
            }
        )

    ok = sum(1 for r in results if r["lat"] is not None)
    print(f"완료: {ok}/{len(results)} 성공", file=sys.stderr)
    # 로그에서 파싱하기 쉽게 JSON을 마커로 감싸 한 줄로 출력.
    print("===GEOCODE_JSON_START===")
    print(json.dumps(results, ensure_ascii=False))
    print("===GEOCODE_JSON_END===")


if __name__ == "__main__":
    main()
