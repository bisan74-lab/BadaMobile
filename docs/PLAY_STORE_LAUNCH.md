# Play Store 런칭 체크리스트

코드 쪽 준비는 끝났고, 아래는 **사람이 계정을 만들고 값을 넣어야 하는 부분**이다.
순서대로 하면 된다.

---

## 1. 계정 만들기

| 계정 | 비용 | 용도 |
|---|---|---|
| [Google Play 개발자 계정](https://play.google.com/console/signup) | **US$25 (1회)** | 앱 배포 |
| [AdMob 계정](https://admob.google.com/) | 무료 | 광고 수익 |

Play 개발자 계정은 개인이면 신분증 확인이 필요하고, 승인까지 보통 1~2일 걸린다.
2023년 이후 만든 개인 계정은 **프로덕션 출시 전에 비공개 테스트(테스터 12명 이상,
14일 연속)** 를 요구할 수 있으니 Play Console 안내를 확인한다.

## 2. AdMob에서 앱 등록 후 ID 두 개 받기

1. AdMob → 앱 → 앱 추가 → Android → "앱이 스토어에 등록되어 있나요?" → 아직 아니면 **아니요**
2. 만들어진 **앱 ID** 복사 — `ca-app-pub-XXXXXXXX~YYYYYYYY` (물결 `~`)
3. 그 앱에서 광고 단위 → **배너** 생성 → **광고 단위 ID** 복사 — `ca-app-pub-XXXXXXXX/YYYYYYYY` (슬래시 `/`)

> 두 ID는 구분자가 다르다(`~` vs `/`). 바꿔 넣으면 광고가 안 나온다.

배너 자리는 물때 화면 하단과 설정 화면 하단 두 곳이다. 단위를 **하나만**
만들어 두 자리가 공유해도 되고, 자리별 수익을 나눠 보고 싶으면 **둘로**
만들어 각각 다른 Secret에 넣는다(4단계 표 참고).

## 3. 업로드 키스토어 만들기

로컬 PC(자바 설치된 환경)에서:

```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

- **이 파일과 비밀번호를 잃어버리면 앱 업데이트를 영원히 못 올린다.** 안전한 곳에 백업한다.
- 저장소에는 절대 커밋하지 않는다(`android/.gitignore`가 이미 막고 있다).

base64로 변환해 둔다(다음 단계에서 Secret에 넣는다):

```bash
base64 -w0 upload-keystore.jks > keystore.base64.txt   # macOS는 -w0 대신 -b0
```

## 4. GitHub Secret 등록

저장소 → Settings → Secrets and variables → Actions → New repository secret

| Secret 이름 | 값 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | 3단계에서 만든 base64 문자열 |
| `ANDROID_KEYSTORE_PASSWORD` | 키스토어 비밀번호 |
| `ANDROID_KEY_ALIAS` | `upload` (keytool에서 지정한 별칭) |
| `ANDROID_KEY_PASSWORD` | 키 비밀번호 |
| `ADMOB_APP_ID` | `ca-app-pub-XXXX~YYYY` |
| `ADMOB_BANNER_AD_UNIT_ID` | 물때 화면 하단 배너 단위 `ca-app-pub-XXXX/YYYY` |
| `ADMOB_SETTINGS_BANNER_AD_UNIT_ID` | (선택) 설정 화면 하단 배너 단위. 없으면 위 값을 함께 쓴다 |
| `DATA_GO_KR_API_KEY` | (이미 등록돼 있음) |

> **`BADAWINDY_TK`는 더 이상 필요 없다**(2026-08-08). 출시 당시엔 이 저장소가
> 비공개라 공개 데이터 저장소에 올리는 크론을 여기서 돌리고 저장소 간
> PAT로 넘겼는데, 그 크론을 `badawindy-data` 자신으로 옮기면서 저장소 간
> 이동이 없어졌다(자기 자신에게 올리므로 기본 `GITHUB_TOKEN`으로 충분).
> 이 저장소엔 이제 이 Secret을 쓰는 워크플로가 없다.

## 5. 공개 데이터 저장소 만들기 (개인정보처리방침 + 바람장)

이 저장소는 지금은 공개이지만, **기상 데이터와 공개 문서는 여전히** 별도의
공개 저장소(`badawindy-data`)에 둔다(코드와 데이터 분리). 데이터 수집
크론도 `badawindy-data` 자신에서 돈다 — 자세한 구조는
[`public_data/README.md`](../public_data/README.md) 참고.

최초 설정 요약:

1. 공개 저장소 `badawindy-data` 생성(기본 브랜치 `main`)
2. `public_data/`의 `privacy-policy.html`·`app_gate.json`을 그 저장소 루트에 올리기
3. 그 저장소 Settings → Pages → Source: `main` / `/ (root)` → Save
   → `https://bisan74-lab.github.io/badawindy-data/privacy-policy.html`
4. `badawindy-data` 저장소 Actions → **Wind data refresh** 수동 실행 →
   바람장이 그 저장소 릴리스에 올라오는지 확인

> Play Console에 등록할 개인정보처리방침 URL은 3번에서 나온 주소이고,
> 앱의 `AppInfo.privacyPolicyUrl`과 같아야 한다.

## 6. AAB 빌드

Actions → **Play Store AAB** → Run workflow

- 필수 Secret이 하나라도 없으면 워크플로가 바로 실패하며 무엇이 빠졌는지 알려준다.
- 성공하면 `store-build-N` 릴리스와 Actions 아티팩트 양쪽에 `app-release.aab`가 올라간다.

## 7. Play Console 등록 — 이 앱의 고유 값만

Console 화면을 따라가는 방법 자체는 검색하면 나오므로 적지 않는다. **여기
저장소에서만 알 수 있는 값**만 남긴다.

| 항목 | 값 |
|---|---|
| 앱 이름 | `바다윈디` |
| 패키지명(변경 불가) | `com.badamobile.bada_mobile` |
| 개인정보처리방침 URL | `https://bisan74-lab.github.io/badawindy-data/privacy-policy.html` |
| 문의 이메일 | `bisan74@gmail.com` |
| 카테고리 | 날씨 |
| 아이콘·피처 그래픽 | `store_assets/` (생성기: `tool/gen_store_assets.py`) |
| 간단한 설명·자세한 설명 | `store_assets/listing_ko.md` |
| 앱에 광고 있음 | **예** (AdMob 배너 2곳) |

### 광고 ID 선언 / 데이터 보안

`google_mobile_ads`(AdMob) SDK의 라이브러리 매니페스트가 `AD_ID` 권한을
자동 병합하므로 **"광고 ID를 사용하나요? → 예"** 로 답해야 한다. "아니요"로
두면 Android 13 이상 타겟 버전이 출시 차단된다.

목적은 두 가지만 고른다. **두 선언(광고 ID / 데이터 보안)의 목적이 서로
어긋나면 안 된다.**

| 데이터 유형 | 수집·공유 | 목적 |
|---|---|---|
| 위치 → 대략적인 위치 | 둘 다 | 광고 또는 마케팅 |
| 기기 또는 기타 ID | 둘 다 | 광고 또는 마케팅 + 사기 예방·보안·규정 준수 |
| 앱 활동 → 앱 상호작용 | 둘 다 | 광고 또는 마케팅 |

- **애널리틱스는 고르지 않는다** — 붙어 있는 SDK가 AdMob 하나뿐이고
  (Firebase Analytics 등 분석 SDK 없음), 광고 노출·클릭 지표는 Play 분류상
  "광고 실적 측정"이라 광고 항목에 이미 포함된다.
- **앱 자체는 위치를 수집하지 않는다** — 매니페스트에 위치 권한이 없고 위치
  플러그인도 쓰지 않는다. 위 "대략적인 위치"는 AdMob이 IP로 추정하는 것이다.
- 정확한 항목은 [AdMob 안내](https://support.google.com/admob/answer/11170392)를
  확인한다.

## 8. 출시 후 할 일

- 공개 데이터 저장소 `app_gate.json`의 `storeUrl`이 실제 스토어 주소와 맞는지
  확인한다(현재 `com.badamobile.bada_mobile` 기준으로 맞춰 둠).
- 새 버전이 스토어에 **실제로 노출된 뒤에** `minSupportedVersion`을 그 버전으로
  올린다(구버전 차단). 순서를 뒤집으면 업데이트할 것이 없는 상태로 모두가
  잠긴다 — [`public_data/README.md`](../public_data/README.md) 참고.
- 광고가 실제로 뜨는지 확인한다. 새 AdMob 광고 단위는 노출까지 **최대 몇 시간**
  걸릴 수 있고, 그동안은 광고 자리에 앱 소개 박스가 보인다(정상 동작).
- AdMob → 앱 설정에서 실제 스토어 항목과 **연결**한다.

---

## 참고: 두 빌드 워크플로의 차이

| | `release-apk.yml` | `release-aab.yml` |
|---|---|---|
| 결과물 | `.apk` | `.aab` |
| 서명 | debug 키 | **업로드 키** |
| 광고 | 테스트 광고 | **실제 광고 ID** |
| 용도 | 기기에 직접 설치해 확인 | **Play Console 제출** |
