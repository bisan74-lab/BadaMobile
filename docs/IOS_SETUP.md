# iOS 대응 — 현재 상태와 남은 일

## 저장소를 나누지 않는다

**같은 저장소, 같은 코드입니다.** Flutter 앱은 `lib/`의 Dart 코드가 두 플랫폼
공통이고, 플랫폼별로 다른 것은 `android/`·`ios/` 폴더의 **설정 파일뿐**이다.
저장소를 나누면 화면 하나 고칠 때마다 두 곳에 같은 수정을 하게 되어 곧
어긋난다.

"빌드 시점 분기"도 대부분 필요 없다. `lib/` 코드는 그대로 두 플랫폼에서
돌고, 갈라야 하는 건 **AdMob 광고 단위 ID 하나**뿐이다(아래).

```
BadaMobile/
├── lib/          ← 두 플랫폼 공통 (99%)
├── android/      ← Android 설정
├── ios/          ← iOS 설정  ← 이번에 추가
└── test/         ← 공통 테스트
```

## 이번에 해 둔 것

| 항목 | 내용 |
|---|---|
| `ios/` 프로젝트 생성 | 번들 ID `com.badamobile.badaMobile` |
| 앱 표시 이름 | `바다윈디` (`CFBundleDisplayName`) |
| 런처 아이콘 | `flutter_launcher_icons`의 `ios: true` — `dart run flutter_launcher_icons`로 생성 |
| AdMob 앱 ID | `Info.plist`의 `GADApplicationIdentifier`. 기본값은 **구글 테스트 ID**, 실제 값은 CI가 `tool/set_ios_admob_id.sh`로 교체 |
| ATT 안내 문구 | `NSUserTrackingUsageDescription` — 없으면 심사에서 거부된다 |
| 광고 단위 ID 분기 | `Env`가 `Platform.isIOS`로 갈라 읽는다 |
| CI | `.github/workflows/ios-build.yml` — 서명 없이 빌드해 **컴파일이 깨졌는지** 확인 |

### 광고 단위 ID는 플랫폼마다 다르다

AdMob은 같은 앱이라도 **Android용 앱과 iOS용 앱을 따로 만들게** 되어 있고,
광고 단위 ID도 각각이다. 서로 바꿔 넣으면 빌드는 되고 **광고만 안 나온다**.

주입 키:

| 플랫폼 | 앱 ID | 배너 단위 |
|---|---|---|
| Android | `ADMOB_APP_ID` (Gradle 환경변수) | `ADMOB_BANNER_AD_UNIT_ID` / `..._SETTINGS_...` |
| iOS | `ADMOB_APP_ID_IOS` (Info.plist 교체) | `ADMOB_BANNER_AD_UNIT_ID_IOS` / `..._SETTINGS_..._IOS` |

iOS 키를 안 주면 **구글 iOS 테스트 단위**로 떨어진다. 안드로이드 단위로
폴백하지 않는다 — 잘못된 플랫폼 단위를 쓰면 조용히 광고가 사라지기 때문이다.

## 남은 일 (사람이 해야 하는 것)

### 1. Apple Developer Program 가입 — **연 US$99**

Android(1회 $25)와 달리 **매년** 낸다. 이게 없으면:
- 실기기 설치 불가(시뮬레이터만)
- App Store 제출 불가
- 푸시 알림 등 일부 기능 불가

지금 단계에서 반드시 필요하지는 않다. **iOS 사용자 수요를 확인한 뒤**
가입해도 된다.

### 2. AdMob에서 iOS 앱 추가
AdMob → 앱 → 앱 추가 → **iOS** → 앱 ID·배너 단위 2개 발급 →
저장소 Secret에 `ADMOB_APP_ID_IOS`, `ADMOB_BANNER_AD_UNIT_ID_IOS`,
`ADMOB_SETTINGS_BANNER_AD_UNIT_ID_IOS` 등록.

### 3. 서명·배포 (Developer Program 가입 후)
- Certificates·Provisioning Profile 발급 → CI Secret에 넣기
- `ios-build.yml`에 `flutter build ipa` + TestFlight 업로드 단계 추가
- App Store Connect에 앱 등록(스토어 문구·스크린샷은 Android 것을 재사용
  가능하지만 **iPhone 해상도 스크린샷을 따로** 찍어야 한다)

### 4. 개인정보 관련 (Apple 필수)
- **App Privacy** 질문지 — Play의 "데이터 보안"과 같은 내용
  (위치·기기 ID·앱 상호작용, 목적은 광고). `PLAY_STORE_LAUNCH.md`의 표를
  그대로 옮기면 된다
- **PrivacyInfo.xcprivacy**(프라이버시 매니페스트) — 플러그인은 각자 포함하고
  있지만, 앱 자체가 `UserDefaults` 같은 "사유 명시 필요 API"를 쓰면 앱 레벨
  매니페스트가 필요할 수 있다. 실제 심사에서 지적되면 추가한다
- ATT 동의 팝업을 띄울지 결정. 안 띄우면 **비개인화 광고**만 나가고
  수익이 다소 낮지만 구현이 없다(현재 상태)

## Mac 없이 어디까지 되나

| 작업 | Mac 필요? |
|---|---|
| `ios/` 설정 수정, Dart 코드 | ❌ (지금 이 저장소에서 다 됨) |
| 컴파일 확인 | ❌ — GitHub Actions **macOS 러너**가 대신 해 준다 |
| 시뮬레이터로 화면 확인 | ✅ |
| 실기기 설치·App Store 제출 | ✅ + Developer Program |

즉 **개발과 검증은 Mac 없이 계속 가능하고**, Mac은 실제 배포 단계에서 필요하다.
(macOS 러너는 요금이 ubuntu의 10배라 `ios-build.yml`은 `ios/`나 `pubspec.lock`이
바뀐 푸시와 수동 실행에서만 돈다. **`pubspec.yaml`을 트리거로 두면 안 된다** —
커밋마다 `version:`을 올리므로 사실상 모든 푸시에서 돌아, 2026-08-06 하루에만
11번 돌았다. `pubspec.lock`은 버전 줄이 없어 패키지가 실제로 바뀔 때만 변한다.)

## 화면이 iOS에서 달라 보일 수 있는 곳

Flutter가 대부분 알아서 처리하지만, 실기기에서 볼 때 확인할 것:

- **상단 노치·하단 홈 인디케이터** — 물때 화면이 전체화면 배경을 쓰므로
  `SafeArea` 처리를 다시 봐야 한다
- **뒤로가기 제스처** — iOS는 하드웨어 뒤로가기가 없다. 상세 예보·정책 화면은
  `Navigator.push`라 스와이프로 닫히지만, 오른쪽 세로 레일로만 이동하는
  구조가 iOS 사용자에게 자연스러운지 봐야 한다
- **글자 크기** — iOS도 Dynamic Type이 있다. `text_scale_layout_test.dart`가
  이미 배율 2.0까지 검사하므로 큰 문제는 없을 것이다
