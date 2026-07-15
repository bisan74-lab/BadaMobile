# BadaMobile (바다모바일)

**물때·조석 정보(바다타임)와 바람·해양 날씨 시각화(윈디)를 하나로 합친 모바일 앱**

낚시, 갯벌 체험, 서핑, 보트 등 바다 활동에 필요한 정보를 한 앱에서 확인합니다.

- 1차 출시: **Android (무료)**
- 2차 확장: **iOS** — Flutter 단일 코드베이스이므로 iOS 빌드 설정만 추가하면 됩니다.

## 주요 기능 (로드맵)

| 영역 | 기능 | 상태 |
|---|---|---|
| 조석/물때 | 지역별 만조·간조 시각, 조위 그래프, 물때(1물~15물) | 스켈레톤 + 목 데이터 |
| 해양 날씨 | 풍향·풍속, 파고, 수온, 시간별 예보 | 스켈레톤 + 목 데이터 |
| 바람 지도 | 윈디 스타일 바람 흐름 시각화 지도 | 예정 |
| 지역 관리 | 포인트 검색, 즐겨찾기 | 스켈레톤 |
| 알림 | 물때/기상 조건 알림 | 예정 |

## 기술 스택

- **Flutter** (Dart) — Android 우선, iOS 확장 대비 크로스플랫폼
- **Riverpod** — 상태 관리
- **http / intl** — API 통신, 날짜·숫자 포맷
- 데이터 소스(연동 예정):
  - [KHOA 바다누리 해양정보서비스](http://www.khoa.go.kr/oceangrid/koofs/kor/observation/obs_real.do) — 조석·조위 (공공 API, 무료)
  - [Open-Meteo Marine API](https://open-meteo.com/en/docs/marine-weather-api) — 파고·수온 (무료)
  - [Open-Meteo Forecast API](https://open-meteo.com/) — 바람·기온 (무료)

현재는 모든 데이터가 **목(mock) 리포지토리**에서 제공되며, 실제 API 연동 시
`lib/features/*/data/repositories/` 의 구현체만 교체하면 됩니다.

## 프로젝트 구조

```
lib/
├── main.dart                  # 앱 진입점
├── app/                       # 앱 셸: 테마, 라우팅, 하단 탭
├── core/                      # 공통 유틸 (물때 계산, 포맷터, API 클라이언트 기반)
├── features/
│   ├── home/                  # 홈 대시보드 (오늘의 물때 + 날씨 요약)
│   ├── tide/                  # 조석·물때 (바다타임 영역)
│   ├── weather/               # 바람·해양 날씨 (윈디 영역)
│   └── locations/             # 지역 선택·즐겨찾기
└── shared/                    # 공용 위젯
test/                          # 단위·위젯 테스트
android/                       # Android 네이티브 설정
```

자세한 설계는 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) 참고.

## 개발 환경 설정

1. [Flutter SDK](https://docs.flutter.dev/get-started/install) 설치 (3.32 이상)
2. 의존성 설치 및 실행:

```bash
flutter pub get
flutter run          # 연결된 Android 기기/에뮬레이터에서 실행 (합성 데이터)

# 실데이터(조석예보·낚시지수)까지 켜려면 공공데이터포털 키 주입:
flutter run --dart-define=DATA_GO_KR_API_KEY=발급받은키
```

3. 검사 및 테스트:

```bash
flutter analyze
flutter test
```

4. 릴리스 빌드 (Android):

```bash
flutter build apk --release        # APK
flutter build appbundle --release  # Play 스토어 업로드용 AAB
```

## iOS 확장 시

```bash
flutter create --platforms ios .
```

를 실행하면 `ios/` 디렉터리가 생성되며 기존 Dart 코드를 그대로 사용합니다.
(macOS + Xcode 필요)
