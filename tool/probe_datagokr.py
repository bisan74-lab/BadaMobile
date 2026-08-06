#!/usr/bin/env python3
"""GitHub 러너에서 data.go.kr에 왜 못 닿는지 층별로 갈라 본다.

2026-08-04부터 `fetch_fishing.py`가 GitHub Actions에서 **응답 없이 타임아웃**
한다. 같은 요청이 한국 IP + 정상 키로는 0.26초에 200을 받는다(실측). 여기서
갈라야 할 것이 두 가지다.

1. **네트워크 층에서 막혔나** — 러너 IP가 차단돼 패킷이 버려지는가.
2. **키가 잘못 들어갔나** — 인증 실패가 반복돼 그 결과로 IP가 막힌 것인가.

둘은 고치는 방법이 완전히 다르다(수집을 한국으로 옮기기 vs Secret 고치기).
그래서 DNS → TCP → TLS → HTTP 순으로 한 층씩 내려가며 어디서 끊기는지 본다.

**키 값은 절대 출력하지 않는다.** 대신 길이와 SHA-256 앞 12자만 찍어,
손에 있는 키와 같은 값인지 비교할 수 있게 한다. 같은 지문을 로컬에서:

    PowerShell:
      $k = Read-Host "인증키"
      [BitConverter]::ToString(
        [Security.Cryptography.SHA256]::Create().ComputeHash(
          [Text.Encoding]::UTF8.GetBytes($k))).Replace("-","").ToLower().Substring(0,12)

    bash:
      printf %s "$KEY" | sha256sum | cut -c1-12

    DATA_GO_KR_API_KEY=... python3 tool/probe_datagokr.py
"""

import hashlib
import json
import os
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HOST = 'apis.data.go.kr'
PATH = '/1192136/fcstFishingv2/GetFcstFishingApiServicev2'
KEY = os.environ.get('DATA_GO_KR_API_KEY', '')
TIMEOUT = 15

UA = 'BadaWindy-DataCollector/1.0 (+https://github.com/bisan74-lab/BadaMobile)'


def step(name):
    print(f'\n── {name}')


def probe_dns() -> list[str]:
    step('1. DNS')
    t = time.time()
    try:
        infos = socket.getaddrinfo(HOST, 443, proto=socket.IPPROTO_TCP)
        ips = sorted({i[4][0] for i in infos})
        print(f'   OK {(time.time() - t) * 1000:.0f}ms → {", ".join(ips)}')
        return ips
    except Exception as e:  # noqa: BLE001
        print(f'   실패: {e!r}')
        return []


def probe_tcp(ips: list[str]) -> None:
    step('2. TCP 443 연결')
    if not ips:
        print('   건너뜀(DNS 실패)')
        return
    for ip in ips:
        t = time.time()
        s = socket.socket()
        s.settimeout(TIMEOUT)
        try:
            s.connect((ip, 443))
            print(f'   {ip}: OK {(time.time() - t) * 1000:.0f}ms')
        except Exception as e:  # noqa: BLE001
            print(f'   {ip}: 실패 {(time.time() - t) * 1000:.0f}ms {e!r}')
        finally:
            s.close()


def probe_tls() -> None:
    step('3. TLS 핸드셰이크')
    t = time.time()
    try:
        ctx = ssl.create_default_context()
        with socket.create_connection((HOST, 443), timeout=TIMEOUT) as raw:
            with ctx.wrap_socket(raw, server_hostname=HOST) as tls:
                print(
                    f'   OK {(time.time() - t) * 1000:.0f}ms '
                    f'{tls.version()} · 인증서 CN='
                    f'{dict(x[0] for x in tls.getpeercert()["subject"]).get("commonName")}'
                )
    except Exception as e:  # noqa: BLE001
        print(f'   실패 {(time.time() - t) * 1000:.0f}ms {e!r}')


def http(label: str, url: str) -> None:
    """상태 코드와 본문 앞부분을 찍는다. 타임아웃과 거부를 구분하는 것이 목적."""
    t = time.time()
    req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept': '*/*'})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
            body = res.read(300)
        print(f'   {label}: {res.status} {(time.time() - t) * 1000:.0f}ms')
        print(f'      {body[:200]!r}')
    except urllib.error.HTTPError as e:
        # 응답은 왔다 — 이것도 중요한 정보다(막힌 것이 아니라 거부된 것).
        print(f'   {label}: HTTP {e.code} {(time.time() - t) * 1000:.0f}ms')
        print(f'      {e.read(200)!r}')
    except Exception as e:  # noqa: BLE001
        print(f'   {label}: 응답 없음 {(time.time() - t) * 1000:.0f}ms {e!r}')


def probe_http() -> None:
    step('4. HTTP')
    http('루트(키 무관)', f'https://{HOST}/')

    bad = urllib.parse.urlencode({
        'serviceKey': 'PROBE-INVALID-KEY',
        'type': 'json',
        'reqDate': time.strftime('%Y%m%d'),
        'pageNo': '1',
        'numOfRows': '1',
    })
    http('잘못된 키 1건', f'https://{HOST}{PATH}?{bad}')

    if not KEY:
        print('   진짜 키: 건너뜀(DATA_GO_KR_API_KEY 가 비어 있다)')
        return
    good = urllib.parse.urlencode({
        'serviceKey': KEY,
        'type': 'json',
        'reqDate': time.strftime('%Y%m%d'),
        'gubun': '갯바위',
        'pageNo': '1',
        'numOfRows': '300',
    })
    http('진짜 키 · 실제 요청과 동일', f'https://{HOST}{PATH}?{good}')


def probe_key() -> None:
    """Secret에 **어떤 값이** 들어 있는지 — 값 자체는 절대 찍지 않는다."""
    step('5. 키 지문 (값은 출력하지 않음)')
    if not KEY:
        print('   DATA_GO_KR_API_KEY 가 비어 있다')
        return
    digest = hashlib.sha256(KEY.encode()).hexdigest()[:12]
    stripped = KEY.strip()
    print(f'   길이 {len(KEY)}자 · SHA-256 앞 12자 {digest}')
    if stripped != KEY:
        print(
            f'   ⚠️ 앞뒤 공백/줄바꿈이 붙어 있다 '
            f'(떼면 {len(stripped)}자, '
            f'{hashlib.sha256(stripped.encode()).hexdigest()[:12]}) '
            f'— Secret을 다시 붙여넣어야 한다'
        )
    if any(c in KEY for c in '%+'):
        print('   ⚠️ % 또는 +가 들어 있다 — 포털의 Encoding 키를 넣었을 수 있다')
    print(f'   앞 2자 {KEY[:2]!r} · 뒤 2자 {KEY[-2:]!r}')


def probe_egress() -> None:
    """이 러너가 어떤 IP로 나가는지. data.go.kr에 문의할 때 필요하다."""
    step('0. 러너 공인 IP')
    try:
        req = urllib.request.Request(
            'https://api.ipify.org?format=json', headers={'User-Agent': UA}
        )
        with urllib.request.urlopen(req, timeout=TIMEOUT) as res:
            print(f'   {json.loads(res.read())["ip"]}')
    except Exception as e:  # noqa: BLE001
        print(f'   확인 실패: {e!r}')


def main() -> int:
    print(f'data.go.kr 진단 — {time.strftime("%Y-%m-%d %H:%M:%SZ", time.gmtime())}')
    probe_egress()
    ips = probe_dns()
    probe_tcp(ips)
    probe_tls()
    probe_http()
    probe_key()
    print(
        '\n읽는 법\n'
        '  루트도 진짜 키도 응답 없음 → **네트워크 차단**. 수집을 한국 IP로 옮겨야 한다.\n'
        '  루트는 오는데 API만 응답 없음 → API 경로만 막힌 것.\n'
        '  진짜 키가 200 → 러너에서도 되는 것이니 간헐적 차단이다.\n'
        '  진짜 키가 오류 응답 → **키 문제**. 위 지문을 손에 있는 키와 비교한다.\n'
    )
    return 0


if __name__ == '__main__':
    sys.exit(main())
