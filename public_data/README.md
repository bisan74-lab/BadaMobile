# 공개 데이터 저장소로 올릴 파일

**기상 데이터와 공개 문서만** 별도의 공개 저장소(`badawindy-data`)에 둔다.

```
BadaMobile        (공개)  소스 코드 전부
badawindy-data    (공개)  이 폴더의 파일 + 데이터 수집 크론 3종 + 릴리스
```

> **2026-08-08 이전엔 BadaMobile이 비공개였다.** 그때는 앱이 비공개 저장소의
> 릴리스 자산·raw 파일을 인증 없이 못 받아서(비공개 저장소의 GitHub Pages도
> 유료 플랜 전용) 데이터만 억지로 분리해 둘 필요가 있었다. 지금은 BadaMobile도
> 공개라 그 이유는 사라졌지만, 코드와 데이터를 나눠 두는 편이 여전히 정리에
> 낫다고 보고 분리 구조는 유지한다. **다만 데이터 수집 크론 자체는
> `badawindy-data`로 옮겼다** — 아래 "데이터 수집 크론" 참고. 여기 BadaMobile
> 쪽엔 더 이상 `wind-data.yml`·`point-forecast.yml`·`fishing-data.yml`이 없다.

## 데이터 수집 크론은 `badawindy-data`에 있다

바람장·지점 예보·낚시지수를 모아 릴리스로 올리는 크론은
[`badawindy-data/.github/workflows/`](https://github.com/bisan74-lab/badawindy-data/tree/main/.github/workflows)
에 있다. **수집 스크립트(`tool/fetch_*.py`)는 옮기지 않고 여기(BadaMobile)에
그대로 둔다** — `badawindy-data`의 워크플로가 매 실행마다 이 저장소를 읽기
전용으로 체크아웃해 그대로 돌린다. 스크립트를 두 곳에 복사해 두면 한쪽만
고치고 잊어버리는 사고가 나므로, 코드는 항상 여기 한 곳에만 둔다(지역
목록 `sample_locations.dart`도 같은 이유로 원본을 그대로 읽힌다).

그래서 이 스크립트를 고치면(`tool/fetch_wind.py` 등) **다음 크론 실행부터
자동으로 반영된다** — 저장소를 오가며 따로 배포할 필요가 없다. 다만 스크립트가
새 파일을 요구하게 되면(새 인자·새 데이터 소스 등) `badawindy-data`
워크플로의 체크아웃 범위·Secret도 함께 봐야 한다.

## 공개 저장소 최초 설정 (`app_gate.json`·`privacy-policy.html`용)

1. GitHub에서 **공개** 저장소 `badawindy-data`를 만든다(기본 브랜치 `main`).
2. 이 폴더의 `privacy-policy.html`과 `app_gate.json`을 그 저장소 **루트**에
   올린다.
3. 그 저장소 Settings → Pages → Source: **Deploy from a branch**,
   브랜치 `main`, 폴더 **`/ (root)`** → Save.
   1~2분 뒤 방침 URL이 살아난다:
   `https://bisan74-lab.github.io/badawindy-data/privacy-policy.html`

## 앱이 이 파일들을 쓰는 방식

| 파일 | 앱에서 쓰는 곳 | 못 받았을 때 |
|---|---|---|
| `wind_field.json.gz` (릴리스) | 지도 바람장 | Open-Meteo 직접 호출 → 캐시 → 합성 |
| `app_gate.json` | 강제 업데이트 게이트 | 게이트 꺼짐(앱은 정상 실행) |
| `privacy-policy.html` | 설정 > 정책, Play Console 등록 URL | 링크만 안 열림 |

주소는 `lib/core/config/env.dart`와 `lib/features/settings/app_info.dart`에
기본값으로 박혀 있고, 빌드 때 `--dart-define`으로 덮을 수 있다.

## 파일을 고칠 때

`app_gate.json`의 값을 바꾸는 것처럼 **즉시 반영이 목적인 변경은 공개
저장소에서 직접** 고치면 된다(앱 재배포 불필요). 여기 있는 사본은 원본
기록용이므로, 공개 저장소만 고쳤다면 나중에 이쪽도 맞춰 둔다.

## 새 버전을 낼 때 — `minSupportedVersion` 올리기

앱은 켜질 때마다 `app_gate.json`을 받아 **자기 버전이 `minSupportedVersion`
보다 낮으면 실행을 막고** 업데이트 안내 화면만 띄운다. 그래서 새 버전을 낼
때마다 이 값을 올려 주면 구버전 사용자가 자동으로 정리된다.

```json
{ "minSupportedVersion": "0.4.6", ... }
```

**순서를 반드시 지킨다.**

1. 새 버전(AAB)을 Play Console에 올리고 **심사 통과 + 프로덕션에 실제로
   노출되는 것까지** 확인한다.
2. 그 다음에 공개 저장소의 `minSupportedVersion`을 새 버전으로 올린다.

> 1번을 건너뛰고 값부터 올리면 **업데이트할 것이 아직 없는 상태에서 모두가
> 잠긴다.** 스토어에 새 버전이 뜨기 전까지 사용자는 안내 화면만 보고 아무것도
> 할 수 없다. Play 단계적 출시(rollout)를 쓴다면 100%가 된 뒤에 올린다.

- `forceUpgrade: true`는 **버전과 무관하게 전부 막는 비상 스위치**다. 서버
  데이터 형식을 갈아엎어 구버전이 전부 못 쓰게 된 경우에만 쓴다.
- 설정을 못 받아오면(오프라인·404 등) 앱은 **항상 정상 실행**된다. 이 폴백은
  건드리지 않는다 — 게이트 확인 실패를 이유로 사용자를 막으면 안 된다.
- 값에 오타가 있거나 숫자가 아닌 조각이 들어가면 버전 비교를 건너뛰고
  통과시킨다(fail-open). 잠기는 쪽으로 실수하지 않게 한 것이다.
