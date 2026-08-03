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
| `BADAWINDY_TK` | 공개 데이터 저장소용 PAT (5단계 참고) |
| `DATA_GO_KR_API_KEY` | (이미 등록돼 있음) |

## 5. 공개 데이터 저장소 만들기 (개인정보처리방침 + 바람장)

이 저장소는 **비공개**라 앱이 여기 있는 파일을 익명으로 받을 수 없고,
비공개 저장소의 GitHub Pages는 유료 플랜 전용이다. 그래서 **기상 데이터와
공개 문서만** 별도의 공개 저장소에 둔다.

절차는 [`public_data/README.md`](../public_data/README.md)에 정리돼 있다.
요약하면:

1. 공개 저장소 `badawindy-data` 생성(기본 브랜치 `main`)
2. `public_data/`의 `privacy-policy.html`·`app_gate.json`을 그 저장소 루트에 올리기
3. 그 저장소 Settings → Pages → Source: `main` / `/ (root)` → Save
   → `https://bisan74-lab.github.io/badawindy-data/privacy-policy.html`
4. `badawindy-data`에 **Contents: Read and write** 권한만 가진 fine-grained PAT 발급
5. 이 저장소 Secret에 `BADAWINDY_TK`로 등록(4단계 표에도 포함)
6. Actions → **Wind data refresh** 수동 실행 → 바람장이 공개 저장소에 올라오는지 확인

> Play Console에 등록할 개인정보처리방침 URL은 3번에서 나온 주소이고,
> 앱의 `AppInfo.privacyPolicyUrl`과 같아야 한다.

## 6. AAB 빌드

Actions → **Play Store AAB** → Run workflow

- 필수 Secret이 하나라도 없으면 워크플로가 바로 실패하며 무엇이 빠졌는지 알려준다.
- 성공하면 `store-build-N` 릴리스와 Actions 아티팩트 양쪽에 `app-release.aab`가 올라간다.

## 7. Play Console 등록

> **입력할 값을 그대로 모아 둔 문서가 따로 있다 —
> [PLAY_CONSOLE_NEW_APP.md](PLAY_CONSOLE_NEW_APP.md).** 아래는 요약이다.

1. 앱 만들기 — 이름 `바다윈디`, 언어 한국어, 앱/게임: **앱**, 무료
2. **프로덕션(또는 내부 테스트)** → 새 버전 만들기 → `app-release.aab` 업로드
3. 스토어 등록정보 준비물:
   - 앱 아이콘 512×512 PNG
   - 그래픽 이미지(피처 그래픽) 1024×500
   - 스크린샷 최소 2장(휴대전화). 물때 타임라인 / 바람지도 / 상세 예보 화면 추천
   - 간단한 설명(80자), 자세한 설명(4000자)
4. **콘텐츠 등급** 설문 — 정보/유틸리티, 부적절 콘텐츠 없음
5. **데이터 보안(Data safety)** 양식 — 아래 6번 참고
6. **광고 포함 여부: 예** 로 체크(AdMob 사용)
7. 대상 연령: 만 13세 이상 권장

### 데이터 보안 양식 작성 기준

앱 자체는 개인정보를 수집하지 않지만 **AdMob이 수집**하므로 다음처럼 답한다.

| 항목 | 답 |
|---|---|
| 데이터를 수집/공유하나요? | **예** (광고 SDK 때문) |
| 위치 – 대략적인 위치 | 수집·공유 O / 목적: **광고 또는 마케팅** |
| 기기 또는 기타 ID (광고 ID) | 수집·공유 O / 목적: **광고 또는 마케팅** |
| 앱 활동 | 광고 상호작용 측정 목적으로 수집 O |
| 전송 중 암호화 | 예 |
| 데이터 삭제 요청 가능 | 앱 삭제 시 기기 내 데이터 제거 |

정확한 항목은 AdMob 문서
([Play 데이터 보안 안내](https://support.google.com/admob/answer/11170392))를 확인한다.

## 8. 출시 후 할 일

- 공개 데이터 저장소 `app_gate.json`의 `storeUrl`이 실제 스토어 주소와 맞는지
  확인한다(현재 `com.badamobile.bada_mobile` 기준으로 맞춰 둠).
- 광고가 실제로 뜨는지 확인한다. 새 AdMob 광고 단위는 노출까지 **최대 몇 시간**
  걸릴 수 있고, 그동안은 광고 자리에 앱 소개 박스가 보인다(정상 동작).

---

## 참고: 두 빌드 워크플로의 차이

| | `release-apk.yml` | `release-aab.yml` |
|---|---|---|
| 결과물 | `.apk` | `.aab` |
| 서명 | debug 키 | **업로드 키** |
| 광고 | 테스트 광고 | **실제 광고 ID** |
| 용도 | 기기에 직접 설치해 확인 | **Play Console 제출** |
