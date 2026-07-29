#!/usr/bin/env python3
"""앱 조석값을 바다타임(badatime.com) 물때표와 자동 대조한다.

서해/남해/동해에서 샘플링한 20개 항구 × 날짜 3개(기본)에 대해:
1. 앱과 동일한 계산으로 만조/간조를 뽑는다 — 조위관측소 실측·예측 조위
   API(10분 시계열) → 국소 극값 + 이웃 3점 포물선 정밀화 → 지점별 2차항
   보정(시간차·조위비) → 다지점이면 거리가중(1/d²) 매칭 극값 보간
   (DataGoKrTideObsRepository와 동일 로직).
2. badatime.com에서 같은 항구의 물때표 페이지를 찾아 같은 날짜의
   만조/간조를 파싱한다. 페이지 구조가 바뀌어도 진단할 수 있게, 파싱
   실패 시 원문 텍스트 발췌를 로그로 남긴다.
3. 시각 차(분)·조위 차(cm)를 표로 출력한다.

GitHub Actions에서 실행한다(DATA_GO_KR_API_KEY Secret + 제한 없는 네트워크).
사용법: python tool/verify_tide.py [YYYYMMDD ...]
"""

import json
import math
import os
import re
import sys
import time as time_mod
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from html import unescape

KEY = os.environ.get("DATA_GO_KR_API_KEY", "")

BASE = "https://apis.data.go.kr/1192136/surveyTideLevel/GetSurveyTideLevelApiService"
BADA = "https://www.badatime.com"
UA = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) BadaMobileVerify/1.0"}

# 앱 sample_locations.dart에서 발췌한 검증 대상 20개 항구(서해7·남해7·동해6).
# (이름, badatime 검색어 후보, lat, lon, [관측소코드], 시간보정분, 조위비)
LOCATIONS = [
    # ── 서해 7 ──
    ("인천", ["인천"], 37.452, 126.592, ["DT_0001"], 0, 1.0),
    ("평택항", ["평택"], 36.966, 126.823, ["DT_0002"], 0, 1.0),
    ("대천항(보령)", ["대천항", "대천"], 36.325, 126.508, ["DT_0025"], 0, 1.0),
    ("군산", ["군산"], 35.975, 126.563, ["DT_0018"], 0, 1.0),
    ("목포", ["목포"], 34.780, 126.375, ["DT_0007"], 0, 1.0),
    ("영흥도", ["영흥도"], 37.245, 126.489, ["DT_0043"], 0, 1.0),
    ("무창포항", ["무창포"], 36.243, 126.522, ["DT_0025", "DT_0051"], 0, 1.0),
    # ── 남해 7 ──
    ("완도", ["완도"], 34.311, 126.755, ["DT_0027"], 0, 1.0),
    ("여수", ["여수"], 34.747, 127.766, ["DT_0016"], 0, 1.0),
    ("통영", ["통영"], 34.846, 128.433, ["DT_0014"], 0, 1.0),
    ("마산", ["마산"], 35.196, 128.570, ["DT_0062"], 0, 1.0),
    ("부산(영도)", ["영도", "부산"], 35.090, 129.035, ["DT_0005"], 0, 1.0),
    ("녹동항", ["녹동"], 34.516, 127.130, ["DT_0026", "DT_0027"], 12, 1.05),
    ("미조항(남해)", ["미조"], 34.686, 128.088, ["DT_0061", "DT_0014", "DT_0016"], 0, 1.0),
    # ── 동해 6 ──
    ("포항", ["포항"], 36.047, 129.384, ["DT_0091"], 0, 1.0),
    ("울산(방어진)", ["방어진", "울산"], 35.500, 129.417, ["DT_0020"], 0, 1.0),
    ("후포", ["후포"], 36.677, 129.453, ["DT_0011"], 0, 1.0),
    ("묵호항", ["묵호"], 37.550, 129.115, ["DT_0006"], 0, 1.0),
    ("속초", ["속초"], 38.207, 128.594, ["DT_0012"], 0, 1.0),
    ("강릉항", ["강릉"], 37.766, 128.951, ["DT_0006", "DT_0057", "DT_0012"], 0, 1.0),
]

# 관측소 좌표(응답 lat/lot이 비면 사용할 폴백 — 활용가이드/앱 검증값 기준).
STATION_COORDS = {
    "DT_0001": (37.452, 126.592), "DT_0002": (36.966, 126.823),
    "DT_0003": (35.426, 126.420), "DT_0005": (35.096, 129.035),
    "DT_0006": (37.550, 129.116), "DT_0007": (34.779, 126.375),
    "DT_0011": (36.677, 129.453), "DT_0012": (38.207, 128.594),
    "DT_0014": (34.827, 128.434), "DT_0016": (34.747, 127.765),
    "DT_0017": (37.007, 126.352), "DT_0018": (35.975, 126.563),
    "DT_0020": (35.501, 129.387), "DT_0024": (36.006, 126.687),
    "DT_0025": (36.406, 126.486), "DT_0026": (34.481, 127.342),
    "DT_0027": (34.315, 126.759), "DT_0029": (34.801, 128.699),
    "DT_0035": (34.684, 125.428), "DT_0043": (37.238, 126.428),
    "DT_0051": (36.128, 126.495), "DT_0057": (37.494, 129.143),
    "DT_0061": (34.924, 128.069), "DT_0062": (35.197, 128.576),
    "DT_0091": (36.051, 129.376),
}


def http_get(url, timeout=30):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


# ── 앱 로직 복제 ──────────────────────────────────────────────


def fetch_day(obs, ymd):
    params = {
        "serviceKey": KEY, "type": "json", "obsCode": obs,
        "reqDate": ymd, "min": "10", "numOfRows": "300",
    }
    url = BASE + "?" + urllib.parse.urlencode(params)
    try:
        body = json.loads(http_get(url))
    except Exception as e:  # 부분 실패는 빈 목록(앱과 동일).
        print(f"    ! {obs} {ymd}: {e}")
        return [], None
    resp = body.get("response", body)
    header = resp.get("header") or {}
    if str(header.get("resultCode", "")) not in ("0", "00"):
        return [], None
    items = ((resp.get("body") or {}).get("items") or {}).get("item") or []
    if isinstance(items, dict):
        items = [items]
    out, coord = [], None
    for it in items:
        t = it.get("obsrvnDt")
        lvl = it.get("tdlvHgt") or it.get("predcTdlvVl") or it.get("bscTdlvHgt")
        if coord is None:
            la, lo = it.get("lat"), it.get("lot")
            try:
                coord = (float(la), float(lo))
            except (TypeError, ValueError):
                coord = None
        if t is None or lvl is None:
            continue
        try:
            out.append((datetime.fromisoformat(str(t).replace(" ", "T")), float(lvl)))
        except ValueError:
            continue
    return out, coord


def extremes(series):
    """국소 극값 + 이웃 3점 포물선 정밀화 + 만조/간조 교대 강제(앱과 동일)."""
    raw = []
    for i in range(1, len(series) - 1):
        (t0, y0), (t1, y1), (t2, y2) = series[i - 1], series[i], series[i + 1]
        is_high = y1 >= y0 and y1 > y2
        is_low = y1 <= y0 and y1 < y2
        if not (is_high or is_low):
            continue
        denom = y0 - 2 * y1 + y2
        d = 0.0 if denom == 0 else max(-0.5, min(0.5, 0.5 * (y0 - y2) / denom))
        half = (t2 - t0).total_seconds() / 2
        raw.append((t1 + timedelta(seconds=d * half), y1 - 0.25 * (y0 - y2) * d, is_high))
    # 조차가 작은 해역(동해)은 평평한 구간에서 같은 종류 극값이 연달아
    # 검출된다 → 같은 종류가 이어지면 더 극단적인 쪽만 남긴다(교대 강제).
    out = []
    for e in raw:
        if out and out[-1][2] == e[2]:
            keep_new = (e[1] > out[-1][1]) if e[2] else (e[1] < out[-1][1])
            if keep_new:
                out[-1] = e
            continue
        out.append(e)
    return out


def dist_km(lat1, lon1, lat2, lon2):
    m = (lat1 + lat2) / 2 * math.pi / 180
    dx = (lon2 - lon1) * math.cos(m) * 111.32
    dy = (lat2 - lat1) * 111.32
    return math.sqrt(dx * dx + dy * dy)


_station_cache = {}


def station_series(obs, day):
    """관측소의 그날 ±1일 시계열(중복 제거)."""
    key = (obs, day.strftime("%Y%m%d"))
    if key in _station_cache:
        return _station_cache[key]
    series, coord = [], None
    for d in (day - timedelta(days=1), day, day + timedelta(days=1)):
        s, c = fetch_day(obs, d.strftime("%Y%m%d"))
        series += s
        coord = coord or c
    series.sort(key=lambda x: x[0])
    dedup = []
    for s in series:
        if not dedup or dedup[-1][0] != s[0]:
            dedup.append(s)
    _station_cache[key] = (dedup, coord or STATION_COORDS.get(obs))
    return _station_cache[key]


def app_extremes(loc, day):
    """앱과 동일한 만조/간조 계산(그날 것만)."""
    name, _, lat, lon, codes, off, scale = loc
    stations = []
    for obs in codes:
        samples, coord = station_series(obs, day)
        if len(samples) < 3:
            continue
        if off or scale != 1.0:
            dt = timedelta(minutes=off)
            samples = [(t + dt, h * scale) for t, h in samples]
        slat, slon = coord if coord else (lat, lon)
        w = 1.0 / max(dist_km(lat, lon, slat, slon), 0.5) ** 2
        stations.append((samples, w))
    if not stations:
        return []
    if len(stations) == 1:
        ex = extremes(stations[0][0])
    else:
        ref = max(stations, key=lambda s: s[1])
        per = [extremes(s[0]) for s in stations]
        lo, hi = day - timedelta(hours=6), day + timedelta(hours=30)
        ex = []
        for t, h, is_high in extremes(ref[0]):
            if not (lo < t < hi):
                continue
            w_sum = t_sum = h_sum = 0.0
            for (samples, w), p in zip(stations, per):
                best, best_diff = None, timedelta(hours=2)
                for tt, hh, ih in p:
                    if ih != is_high:
                        continue
                    diff = abs(tt - t)
                    if diff <= best_diff:
                        best, best_diff = (tt, hh), diff
                if best is None:
                    continue
                w_sum += w
                t_sum += w * best[0].timestamp()
                h_sum += w * best[1]
            if w_sum > 0:
                ex.append((datetime.fromtimestamp(t_sum / w_sum), h_sum / w_sum, is_high))
        ex.sort(key=lambda e: e[0])
    nxt = day + timedelta(days=1)
    return [(t, h, ih) for t, h, ih in ex if day <= t < nxt]


# ── badatime.com ──────────────────────────────────────────────


def anchors(html):
    """(href, text) 목록."""
    out = []
    for m in re.finditer(r'<a\b[^>]*href="([^"#]+)"[^>]*>(.*?)</a>', html, re.S | re.I):
        text = re.sub(r"<[^>]+>", "", m.group(2))
        out.append((m.group(1), unescape(text).strip()))
    return out


def to_text(html):
    html = re.sub(r"<(script|style)[^>]*>.*?</\1>", " ", html, flags=re.S | re.I)
    html = re.sub(r"<(td|th|tr|div|p|li|br|h\d)[^>]*>", "\n", html, flags=re.I)
    text = re.sub(r"<[^>]+>", " ", html)
    return re.sub(r"[ \t]+", " ", unescape(text))


def discover_badatime(names_needed):
    """홈 + 1단계 하위 페이지에서 지점명→URL을 찾는다."""
    link_map = {}
    seen_pages = set()

    def scan(url):
        if url in seen_pages or len(seen_pages) > 60:
            return []
        seen_pages.add(url)
        try:
            html = http_get(url)
        except Exception as e:
            print(f"  ! badatime {url}: {e}")
            return []
        time_mod.sleep(0.2)
        found = anchors(html)
        for href, text in found:
            if not text or len(text) > 25:
                continue
            full = urllib.parse.urljoin(url, href)
            if "badatime" not in urllib.parse.urlparse(full).netloc:
                continue
            link_map.setdefault(text, full)
        return found

    home_links = scan(BADA + "/")
    # 사이트맵도 시도(있으면 URL 패턴 파악에 유용).
    try:
        sm = http_get(BADA + "/sitemap.xml", timeout=15)
        urls = re.findall(r"<loc>([^<]+)</loc>", sm)[:2000]
        print(f"  sitemap: {len(urls)}개 URL, 예시: {urls[:8]}")
    except Exception:
        print("  sitemap 없음")
    # 홈에서 지역/목록처럼 보이는 링크를 1단계만 따라간다.
    region_words = ("서해", "남해", "동해", "제주", "경기", "인천", "충남", "충청",
                    "전북", "전남", "전라", "경남", "경북", "경상", "강원", "부산",
                    "울산", "물때", "지역", "전국")
    for href, text in home_links:
        if any(w in text for w in region_words):
            scan(urllib.parse.urljoin(BADA + "/", href))
        if len(seen_pages) > 45:
            break

    result = {}
    for name_terms in names_needed:
        best = None
        for term in name_terms:
            # 완전 일치 > 시작 일치 > 포함.
            exact = [u for t, u in link_map.items() if t == term]
            starts = [u for t, u in link_map.items() if t.startswith(term)]
            contains = [u for t, u in link_map.items() if term in t]
            for cand in (exact, starts, contains):
                if cand:
                    best = cand[0]
                    break
            if best:
                break
        result[name_terms[0]] = best
    print(f"  링크맵 {len(link_map)}건 수집(페이지 {len(seen_pages)}개)")
    unmatched = [k for k, v in result.items() if not v]
    if unmatched:
        print(f"  ! URL 못 찾음: {unmatched}")
        sample = sorted(link_map.items())[:120]
        print("  수집된 링크 예시(진단용):")
        for t, u in sample:
            print(f"    {t} -> {u}")
    return result


DATE_PATTERNS = [
    lambda d: rf"{d.year}[.\-/]0?{d.month}[.\-/]0?{d.day}\b",
    lambda d: rf"0?{d.month}월\s*0?{d.day}일",
    lambda d: rf"\b0?{d.month}\.0?{d.day}\b",
]
ENTRY_RE = re.compile(r"(만조|간조)\s*(\d{1,2}:\d{2})\s*\(?\s*(-?\d+)\s*\)?")


def bada_extremes(page_text, day):
    """페이지 텍스트에서 해당 날짜 구간의 만조/간조를 뽑는다."""
    # 날짜 마커들의 위치를 모두 찾는다(모든 날짜 패턴).
    markers = []  # (pos, date)
    for delta in range(-16, 17):
        d = day + timedelta(days=delta)
        for pat in DATE_PATTERNS:
            for m in re.finditer(pat(d), page_text):
                markers.append((m.start(), d.date()))
    if not markers:
        return None, "날짜 마커 없음"
    markers.sort()
    # 대상 날짜 마커 → 다음 마커 전까지가 그날 구간.
    result = []
    for i, (pos, d) in enumerate(markers):
        if d != day.date():
            continue
        end = markers[i + 1][0] if i + 1 < len(markers) else len(page_text)
        seg = page_text[pos:end]
        for kind, hm, height in ENTRY_RE.findall(seg):
            h, mnt = map(int, hm.split(":"))
            result.append((h * 60 + mnt, int(height), kind == "만조"))
        if result:
            break
    if not result:
        return None, "구간에서 만조/간조 못 찾음"
    # 중복 제거(같은 시각).
    seen, dedup = set(), []
    for t, h, ih in sorted(result):
        if t not in seen:
            seen.add(t)
            dedup.append((t, h, ih))
    return dedup, None


def probe():
    """badatime.com 페이지 구조 정찰: 인천을 예로 실제 물때표 URL을 찾는다."""
    html = http_get(BADA + "/")
    links = anchors(html)
    print(f"홈 앵커 {len(links)}개. '인천'/'물때' 포함 앵커:")
    for href, text in links:
        if "인천" in text or "물때" in text:
            print(f"  '{text}' -> {href}")
    tried = set()

    def inspect(u, depth):
        if u in tried or len(tried) > 25:
            return
        tried.add(u)
        try:
            h = http_get(u)
        except Exception as e:
            print(f"\n## {u}: 실패 {e}")
            return
        time_mod.sleep(0.2)
        title = re.search(r"<title>(.*?)</title>", h, re.S)
        n_manjo = h.count("만조")
        times = len(re.findall(r"\d{1,2}:\d{2}", h))
        print(f"\n## {u}\n   {len(h)}B, 만조 {n_manjo}회, 시각패턴 {times}개, "
              f"title={unescape(title.group(1)).strip()[:70] if title else '?'}")
        if n_manjo >= 4:
            i = h.find("만조")
            print("   ---- RAW HTML 발췌(만조 주변 3000자) ----")
            print(h[max(0, i - 600) : i + 2400])
            print("   ---- 발췌 끝 ----")
            txt = to_text(h)
            j = txt.find("만조")
            print("   ---- TEXT 발췌(만조 주변 1500자) ----")
            print(txt[max(0, j - 300) : j + 1200])
            print("   ---- 발췌 끝 ----")
            return
        if depth <= 0:
            return
        for hr, tx in anchors(h):
            full = urllib.parse.urljoin(u, hr)
            if "badatime" not in urllib.parse.urlparse(full).netloc:
                continue
            if any(w in tx for w in ("물때", "조석", "인천")) or "/tide" in hr:
                print(f"   link: '{tx.strip()[:30]}' -> {full}")
                inspect(full, depth - 1)

    for cand in (
        f"{BADA}/158/tide",
        f"{BADA}/158",
        f"{BADA}/tide/158",
        f"{BADA}/158/tide-calendar",
    ):
        inspect(cand, 1)


def main():
    if not KEY:
        sys.exit("DATA_GO_KR_API_KEY 환경변수가 없습니다.")
    args = [a for a in sys.argv[1:] if a.strip()]
    if args and args[0] == "--probe":
        probe()
        return
    if args:
        dates = [datetime.strptime(a, "%Y%m%d") for a in args]
    else:
        base = datetime.now()
        dates = [base + timedelta(days=1), base + timedelta(days=3), base + timedelta(days=6)]
        dates = [datetime(d.year, d.month, d.day) for d in dates]
    print(f"검증 날짜: {[d.strftime('%Y-%m-%d') for d in dates]}")

    print("\n[1/3] badatime.com 지점 URL 탐색")
    urls = discover_badatime([loc[1] for loc in LOCATIONS])

    print("\n[2/3] 지점별 비교")
    dumped_sample = False
    summary = []  # (name, date, n_matched, max_dt_min, max_dh_cm, note)
    for loc in LOCATIONS:
        name = loc[0]
        url = urls.get(loc[1][0])
        print(f"\n=== {name} ===  badatime: {url or '(URL 없음)'}")
        page_text = None
        if url:
            try:
                page_text = to_text(http_get(url))
                time_mod.sleep(0.3)
            except Exception as e:
                print(f"  ! 페이지 로드 실패: {e}")
        for day in dates:
            app = app_extremes(loc, day)
            app_str = " · ".join(
                f"{'만조' if ih else '간조'} {t:%H:%M}({h:.0f})" for t, h, ih in app
            )
            print(f"  {day:%m-%d} APP : {app_str or '없음'}")
            if page_text is None:
                summary.append((name, day, 0, None, None, "badatime 페이지 없음"))
                continue
            bada, err = bada_extremes(page_text, day)
            if bada is None:
                print(f"  {day:%m-%d} BADA: 파싱 실패({err})")
                summary.append((name, day, 0, None, None, f"파싱 실패({err})"))
                if not dumped_sample:
                    dumped_sample = True
                    print("  ---- 페이지 텍스트 발췌(진단용, 2500자) ----")
                    print(page_text[:2500])
                    print("  ---- 발췌 끝 ----")
                continue
            bada_str = " · ".join(
                f"{'만조' if ih else '간조'} {t // 60:02d}:{t % 60:02d}({h})"
                for t, h, ih in bada
            )
            print(f"  {day:%m-%d} BADA: {bada_str}")
            # 같은 종류·가장 가까운 시각끼리 매칭해 차이 계산.
            diffs = []
            for t, h, ih in app:
                tm = t.hour * 60 + t.minute
                cands = [(abs(bt - tm), bt, bh) for bt, bh, bih in bada if bih == ih]
                if not cands:
                    continue
                dmin, bt, bh = min(cands)
                if dmin <= 120:
                    diffs.append((dmin, abs(h - bh)))
            if diffs:
                max_dt = max(d[0] for d in diffs)
                max_dh = max(d[1] for d in diffs)
                print(f"        매칭 {len(diffs)}/{len(app)}: 최대 시각차 {max_dt}분, 최대 조위차 {max_dh:.0f}cm")
                summary.append((name, day, len(diffs), max_dt, max_dh, ""))
            else:
                summary.append((name, day, 0, None, None, "매칭 극값 없음"))

    print("\n[3/3] 요약(항구 × 날짜: 최대 시각차/조위차)")
    print(f"{'항구':<12} {'날짜':<6} {'매칭':<4} {'시각차(분)':<9} {'조위차(cm)':<9} 비고")
    for name, day, n, dt, dh, note in summary:
        dt_s = "-" if dt is None else str(dt)
        dh_s = "-" if dh is None else f"{dh:.0f}"
        print(f"{name:<12} {day:%m-%d}  {n:<4} {dt_s:<9} {dh_s:<9} {note}")


if __name__ == "__main__":
    main()
