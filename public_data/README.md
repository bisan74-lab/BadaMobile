# 공개 데이터 저장소로 올릴 파일

코드 저장소(`BadaMobile`)는 **비공개**라 앱이 여기 있는 파일을 직접 받을 수
없다(릴리스 자산·raw 파일 모두 인증이 필요하고, 비공개 저장소의 GitHub
Pages는 유료 플랜 전용이다). 그래서 **기상 데이터와 공개 문서만** 별도의
공개 저장소에 둔다.

```
BadaMobile        (비공개)  소스 코드 전부
badawindy-data    (공개)    이 폴더의 파일 + 바람장 릴리스
```

공개되는 것은 **기상 데이터와 개인정보처리방침뿐**이고 소스는 노출되지 않는다.

## 공개 저장소 최초 설정

1. GitHub에서 **공개** 저장소 `badawindy-data`를 만든다(기본 브랜치 `main`).
2. 이 폴더의 `privacy-policy.html`과 `app_gate.json`을 그 저장소 **루트**에
   올린다.
3. 그 저장소 Settings → Pages → Source: **Deploy from a branch**,
   브랜치 `main`, 폴더 **`/ (root)`** → Save.
   1~2분 뒤 방침 URL이 살아난다:
   `https://bisan74-lab.github.io/badawindy-data/privacy-policy.html`
4. PAT 발급: 코드 저장소의 크론이 여기에 바람장을 올려야 한다.
   GitHub Settings → Developer settings → Personal access tokens →
   **Fine-grained token** → Repository access: `badawindy-data`만 →
   Permissions: **Contents: Read and write** → 생성 후 값 복사.
5. **코드 저장소**(BadaMobile) Settings → Secrets and variables → Actions에
   `PUBLIC_DATA_TOKEN` 이름으로 그 PAT를 등록한다.
   저장소 이름을 다르게 지었다면 같은 화면 **Variables** 탭에
   `PUBLIC_DATA_REPO` = `소유자/저장소이름` 도 함께 등록한다.
6. 코드 저장소 Actions → **Wind data refresh** 를 수동 실행해,
   `badawindy-data`에 `wind-data` 릴리스와 `wind_field.json.gz`가
   올라오는지 확인한다.

## 앱이 이 파일들을 쓰는 방식

| 파일 | 앱에서 쓰는 곳 | 못 받았을 때 |
|---|---|---|
| `wind_field.json.gz` (릴리스) | 지도 바람장 | Open-Meteo 직접 호출 → 캐시 → 합성 |
| `app_gate.json` | 강제 업데이트 게이트 | 게이트 꺼짐(앱은 정상 실행) |
| `privacy-policy.html` | 설정 > 정책, Play Console 등록 URL | 링크만 안 열림 |

주소는 `lib/core/config/env.dart`와 `lib/features/settings/app_info.dart`에
기본값으로 박혀 있고, 빌드 때 `--dart-define`으로 덮을 수 있다.

## 파일을 고칠 때

`app_gate.json`의 `forceUpgrade`를 켜는 것처럼 **즉시 반영이 목적인 변경은
공개 저장소에서 직접** 고치면 된다(앱 재배포 불필요). 여기 있는 사본은
원본 기록용이므로, 공개 저장소만 고쳤다면 나중에 이쪽도 맞춰 둔다.
