# BadaMobile 초기 구조 설계

> 입력 문서: [REQUIREMENTS.md](REQUIREMENTS.md) — FR/NFR ID를 본 문서에서 추적한다.

## 화면 구조와 흐름

```
AppShell (하단 탭)
├── 홈        HomeScreen        FR-07  오늘 요약: 물때 + 다음 만조/간조 + 현재 바람·파고
├── 물때      TideScreen        FR-01~04  날짜 이동, 물때 배지, 조위 그래프, 만조/간조 목록
├── 날씨      WeatherScreen     FR-05, FR-12  현재 요약, 바람지도(예정), 시간별 예보
└── 지역      LocationsScreen   FR-06  검색, 선택, 즐겨찾기
```

- 지역 변경은 `selectedLocationProvider` 하나로 전파된다 — 화면 간 별도 네비게이션 연동 불필요.
- 새 기능(예: 주간 물때표, 알림 설정)은 `features/` 아래 새 디렉터리로 추가한다.

## 설계 원칙

- **Feature-first 구조**: 화면·상태·데이터를 기능 단위(`tide`, `weather`, `locations`, `home`)로 묶어
  기능 추가/삭제가 다른 영역에 영향을 주지 않도록 한다.
- **Repository 패턴**: UI는 리포지토리 인터페이스에만 의존한다. 현재는 목(mock) 구현을 주입하며,
  실제 API 연동 시 구현체만 교체한다.
- **Riverpod**: Provider를 통해 리포지토리를 주입하고 화면 상태를 관리한다.
  테스트에서 `ProviderScope(overrides: ...)`로 목을 주입할 수 있다.

## 레이어 구성

```
presentation (screens, widgets, providers)
        │  Riverpod Provider로 주입
        ▼
domain-ish (models, repository 인터페이스)
        ▼
data (repository 구현: mock → 추후 KHOA / Open-Meteo API)
```

## 기능별 책임

### features/tide — 조석·물때 (바다타임 영역)
- `TideRepository`: 특정 지역·날짜의 만조/간조 이벤트와 시간별 조위 곡선 제공
- 물때(1물~15물, 조금/사리) 계산은 `core/utils/mul_ttae.dart` 에서 음력 기반 표준 공식으로 처리
- 화면: 일간 조석표, 조위 그래프(CustomPaint), 물때 배지

### features/weather — 바람·해양 날씨 (윈디 영역)
- `MarineWeatherRepository`: 시간별 풍향·풍속·돌풍·파고·수온 예보 제공
- 화면: 시간별 예보 리스트, 풍향 화살표, 요약 카드
- **바람 지도(파티클 애니메이션)** 는 2단계 과제 — `WindMapScreen` 에 자리만 잡아 둠.
  구현 시 후보: `flutter_map` + 커스텀 파티클 레이어, 또는 WebView + leaflet-velocity

### features/locations — 지역
- 해양 관측 지점(포인트) 목록·검색, 즐겨찾기(추후 `shared_preferences` 영속화)
- 선택된 지역은 앱 전역 상태(`selectedLocationProvider`)로 공유되어 tide/weather 화면이 반응

### features/home — 홈 대시보드
- 선택 지역의 "오늘": 물때, 다음 만조/간조, 현재 바람·파고 요약

## 데이터 소스 연동 설계 (FR-08, FR-09)

### API 후보 조사 결과 (해양 기상, "최소 2주 예보" 기준)

| 후보 | 예보 기간 | 제공 항목 | 비용/키 | 판정 |
|---|---|---|---|---|
| **Open-Meteo Marine + Forecast** | **16일** | 파고·파주기·파향·수온 / 풍속·돌풍·풍향·기온 | 무료(비상업)·키 불필요 | **채택** |
| Windy Point Forecast API | 10일 | 바람·파도 등 | 유료 | 제외(무료 앱 원칙) |
| 기상청 단기예보/중기예보 API | 3일/10일 | 바람·기온 (파고는 해상예보 별도) | 무료·키 필요 | 2주 미달, 보조 후보 |
| NOAA GFS/WaveWatch3 원자료 | 16일 | 원시 격자 데이터 | 무료 | 직접 전처리 서버 필요, 제외 |
| KHOA 바다누리 Open API | 조석 연 단위 | 조석예보·조위·수온 | 무료·키 필요 | **조석용 채택(예정)** |

Open-Meteo Marine API는 hourly 변수로 `wave_height, wave_period, wave_direction,
sea_surface_temperature` 등을 제공하고 `forecast_days` 는 1~16일(기본 7일)이다.
Forecast API에서 `wind_speed_10m, wind_gusts_10m, wind_direction_10m, temperature_2m`
(단위 m/s)를 함께 받아 시간축으로 병합한다.

### 데이터 제공 범위 정책

| 데이터 | 범위 | 근거/구현 |
|---|---|---|
| 해양 기상(바람·파고·파주기) | 16일 (`defaultForecastHours`) | FR-05, Open-Meteo 한도 |
| 조석(만조/간조·조위) | 오늘 기준 ±1년 (`maxTideForecastRange`) | FR-15, 범위 밖은 `DataRangeException` |
| 단순 물때(명칭만) | 미래 2년 (`maxSimpleMulTtaeRange`) | FR-16, 근사 음력 기반 |

### 연동 구현 현황

```
OpenMeteoMarineRepository implements MarineWeatherRepository   [구현됨]
  GET https://marine-api.open-meteo.com/v1/marine
      ?latitude&longitude&forecast_days=16
      &hourly=wave_height,wave_period,wave_direction,sea_surface_temperature
  GET https://api.open-meteo.com/v1/forecast
      ?latitude&longitude&forecast_days=16&wind_speed_unit=ms
      &hourly=wind_speed_10m,wind_gusts_10m,wind_direction_10m,temperature_2m
  두 응답을 시간축 기준으로 병합해 HourlyMarine[] 생성 (null은 직전 값으로 채움)

FallbackMarineWeatherRepository                                 [구현됨]
  실데이터 호출 실패(오프라인 등) 시 MockMarineWeatherRepository로 폴백 (NFR-03)

DataGoKrFishingRepository implements FishingRepository          [뼈대 구현]
  End Point: https://apis.data.go.kr/1192136/fcstFishingv2  (활용신청 승인됨)
  인증: 공공데이터포털 일반 인증키 (--dart-define=DATA_GO_KR_API_KEY=...)
  공통 응답 봉투(response.header/body.items.item) 파싱 완료.
  ⚠️ item 필드 매핑은 포털 활용가이드/샘플 응답 확인 후 확정 →
     확정 전까지 fishingRepositoryProvider는 MockFishingRepository 사용.

KhoaTideRepository implements TideRepository                    [계획, v0.2]
  GET /api/oceangrid/tideObcPreTab/search.do   조석예보(만조/간조) → TideExtreme[]
  GET /api/oceangrid/tideObcPre/search.do      1시간 조위 예측     → hourlyHeightsCm
  파라미터: ServiceKey, ObsCode(SeaLocation.khoaStationCode), Date(yyyyMMdd)
  ※ KHOA 조석예보는 연간 조석표 기반이라 미래 1년 요구(FR-15)를 충족한다.
```

API 키(KHOA)는 `--dart-define=KHOA_API_KEY=...` 로 주입한다 (`core/config/env.dart`).
저장소에 키를 커밋하지 않는다 (NFR-04). Open-Meteo는 키가 필요 없다.

- 전환 방법: `tideRepositoryProvider` / `marineWeatherRepositoryProvider` 에서
  구현체만 교체한다. UI 코드는 변경 없음. 테스트는 provider override로 목을 주입한다.

### 캐싱·오프라인 설계 (FR-11, NFR-03, v0.3)

```
Repository 구현 내부에 2계층 캐시:
  1) 메모리: Riverpod FutureProvider 캐시 (현재 동작)
  2) 디스크: (지역 id, 날짜) 키로 JSON 저장 — shared_preferences 또는 경량 파일 캐시
네트워크 실패 시: 디스크 캐시 → 없으면 오류 카드 표시 (한국어 메시지)
```

### 오류 처리 정책 (NFR-03)

- Repository는 실패 시 도메인 예외(`DataUnavailableException` 등, 추후 `core/errors/`)를 던진다.
- 화면은 `AsyncValue.when(error:)` 에서 사용자용 한국어 메시지로 변환해 표시한다.
- API 응답 파싱 실패는 로그(추후 crashlytics 검토) 후 캐시로 폴백한다.

## 상태 관리 규칙

- 전역 상태: 선택 지역, 즐겨찾기 → `locations/presentation/providers.dart`
- 화면 상태: `FutureProvider.family` 로 (지역, 날짜) 파라미터화된 비동기 데이터 로드
- 위젯은 가능한 한 `ConsumerWidget` 으로 얇게 유지

## 테스트 전략

- `core/utils` 순수 함수(물때 계산 등)는 단위 테스트 필수
- 리포지토리 목 구현은 그 자체로 테스트 픽스처 역할
- 화면은 스모크 위젯 테스트(렌더링 + 핵심 텍스트 존재) 수준으로 시작

## 모듈 의존 규칙

```
app/        → features/*  (화면 조립만)
features/A  → core/, shared/, 그리고 다른 feature의 "공개 provider"만
core/       → 외부 패키지만 (features를 알지 못함)
shared/     → core/ 만
```

- feature 간 직접 위젯 import는 지양하고, 공유가 필요한 상태는 provider로 노출한다.
  (현재 허용된 교차 의존: home → tide/weather/locations의 provider와 WindArrow)
- 순환 의존이 생기면 해당 모델/로직을 `core/` 로 승격한다.

## 요구사항 추적 요약

| 요구사항 | 담당 모듈 |
|---|---|
| FR-01~04 (물때/조석) | `features/tide`, `core/utils/mul_ttae.dart` |
| FR-05 (해양 예보) | `features/weather` |
| FR-06 (지역) | `features/locations` |
| FR-07 (홈 요약) | `features/home` |
| FR-08/09 (실데이터) | 각 feature `data/repositories/` 신규 구현체 |
| FR-12 (바람 지도) | `features/weather` 내 신규 화면/레이어 |
| NFR-06 (품질) | `analysis_options.yaml`, `test/`, `.github/workflows/ci.yml` |

## iOS 확장 (NFR-01)

Dart 코드는 플랫폼 독립적이다. iOS 추가 시:
1. `flutter create --platforms ios .` 로 `ios/` 생성
2. 서명·번들 ID 설정 (`com.badamobile.app`)
3. 알림 등 플랫폼 기능 사용 시 iOS 권한 설정 추가
