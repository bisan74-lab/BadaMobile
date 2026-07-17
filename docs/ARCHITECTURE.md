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
- 화면: `TideDatePicker`(연도→월→일 계층 날짜 선택기) + 그래픽 물때 카드
  (`_TideGraphicBody`, 바다타임 스타일 참고해 v0.5에서 개편)
  - `TideDatePicker`(`widgets/tide_date_picker.dart`): 연도 행 → 월 행 → 일 행 3단
    가로 스크롤. 연도/월을 탭하면 그 해·달로 이동하고, 일 행에 해당 달 날짜와
    물때가 표시되어 좌우 스크롤로 고른다. `date`가 바뀌면 세 행 모두 선택
    항목이 중앙에 오도록 자동 스크롤. 진입 시 오늘 날짜가 기본 선택되며,
    범위는 조석 ±1년 / 물때 2년([maxTideForecastRange], [maxSimpleMulTtaeRange]).
  - `_TideGraphicBody`(`tide_screen.dart`): 바다색 그라디언트 카드 위에
    날짜·음력일·물때 배지·`MoonPhaseIcon`(월령 기반 달 위상)·
    `TideCurrentStrengthBar`(하루 조위 변화폭 기준 정성적 조류세기)를 얹고,
    그 아래 **상세 조위 그래프(`TideChart`) → 날짜 이동 버튼 → 만조/간조
    타임라인(`TideTimeline`)** 순서로 배치한다(그래프를 먼저 보고 싶다는
    피드백으로 순서 변경). 그래프는 접었다 펴는 구조가 아니라 항상 펼쳐진
    채로 보인다.
  - `TideTimeline`(`widgets/tide_timeline.dart`): 0~24시 세로 축을 화면 중앙에
    두고, 만조는 축 왼쪽·간조는 축 오른쪽에 카드를 배치해 좌우 공간을 고르게
    쓴다(초기 버전은 전부 왼쪽에만 배치해 오른쪽이 비어 보인다는 피드백으로
    개편). 이전 극값 대비 조위 증감(▲▼) 표시, 오늘이면 현재 시각선을 그린다.
  - `MoonPhaseIcon`(`widgets/moon_phase_icon.dart`): `lunarAgeDays()`로 구한
    월령을 0~1 위상으로 정규화해 초승~보름~그믐 형태를 `CustomPainter`로 그린다
    (장식용 지표, 정밀 천문 계산 아님).
  - `TideRepository.withFallback`은 관측소 코드 미보유(`Exception`)와 범위 초과
    (`DataRangeException`)를 구분한다 — 코드가 없는 지점은 합성 데이터로
    자연스럽게 폴백하고, 범위 초과만 사용자에게 안내 카드로 알린다.

### features/weather — 바람·해양 날씨 (윈디 영역)
- `MarineWeatherRepository`: 시간별 풍향·풍속·돌풍·파고·수온 예보 제공
- **`WeatherScreen`이 곧 윈디 스타일 지도다** (v0.5 개편) — 별도 라우팅 없이
  탭 진입 즉시 지도가 첫 화면으로 뜬다.
- 화면 구조는 `Stack`이다(스크롤 페이지가 아니다): 지도가 화면 전체를
  차지하고(`Positioned.fill`), 그 위에 하단 정보 바가 겹쳐 뜬다
  (`Positioned(bottom: 0, ...)`). 처음엔 지도를 `CustomScrollView`로 감싸
  "아래로 스크롤하면 정보가 보이는" 구조였는데, 그러면 지도의 핀치 줌/팬
  제스처가 페이지 스크롤과 경쟁해 확대가 잘 안 먹는 문제가 있어 윈디처럼
  지도는 항상 전체화면 + 항상 조작 가능, 상세 정보는 지도 위에 겹치는
  바텀시트로 바꿨다.
  - 지도(`_WindMapArea`, `InteractiveViewer`로 항상 감쌈): 풍속 색상
    히트맵 + 파티클 흐름 + 해안선 + 지점 표시. **아무 곳이나 탭하면**
    가장 가까운 지점이 선택된다(`_nearestLocation`, 위경도 유클리드 거리
    최근접) — 개별 마커를 정확히 눌러야 하던 것에서 개편.
    - `windSpeedColor()`/`windSpeedRgb()`(`widgets/wind_heatmap.dart`): 윈디
      스타일 m/s→색상 스케일(파랑→청록→초록→노랑→주황→빨강→자주, 태풍급
      강풍을 자주/보라로 표현). `buildWindHeatmapImage()`가 격자를 144×108
      래스터로 구워 `ui.Image`를 만들고, `WindHeatmapPainter`가 이를 캔버스에
      확대해 그린다 — 매 파티클 프레임(60fps)이 아니라 시간 스크러버로 필드가
      바뀔 때만 다시 굽는다(`_WindMapAreaState._rebuildHeatmap`). 히트맵은
      지도와 같은 `InteractiveViewer` 자식이라 확대/축소해도 색상이 그대로
      유지된다.
    - 파티클(흰 점) 궤적 길이는 그 지점의 순간 풍속에 비례한다
      (`_WeatherScreenState._onTick`의 `maxTrail` 계산) — 약한 바람은 짧은
      점, 강한 바람은 길게 늘어진 흐름선으로 보인다.
    - `CoastlinePainter`(`widgets/coastline_painter.dart`): 실제 국경·해안선을
      그린다. 좌표 출처는 Natural Earth 1:50m Admin 0 Countries(공개
      도메인, https://github.com/nvkelso/natural-earth-vector) — 한국·
      북한·중국·일본·대만 지오메트리만 추출해 화면 크기에 맞게 단순화한 뒤
      `country_borders_data.dart`에 정적 데이터로 박아 넣었다(런타임에 지도
      타일을 받아오지 않음, 앱이 별도 지도 서비스에 의존하지 않는다).
    - `MapProjection`/`LatLonBounds`(`widgets/map_projection.dart`): 지도의
      모든 레이어(해안선·히트맵·마커·지명)가 공유하는 위경도↔캔버스 좌표
      변환(정방향 `project`/`x`/`y`, 역방향 `latFor`/`lonFor` — 탭한 화면
      좌표를 위경도로 되돌릴 때 쓴다). 지도 기본 화면뷰(`mapViewBounds`,
      23~42°N·116~134°E — 윈디 기본 줌 수준 참고)와 바람장 격자 범위를
      **동일하게** 맞춰 지도 전체에 바람 히트맵이 채워지도록 했다 —
      Open-Meteo는 위경도만 주면 전 세계 어디든 응답하므로, 별도의
      "글로벌 기상 API" 연동 없이 기존 리포지토리의 격자 범위
      (`OpenMeteoWindFieldRepository.minLat` 등)만 넓히면 된다(현재
      10×12=120 격자점).
    - `MapCityLabelLayer`(`widgets/map_city_labels.dart`): 서울·부산 등
      주요 도시 이름을 항상 표시(윈디의 도시 라벨 참고). 41개 지점(군산·
      태안 등) 마커의 이름은 평소엔 선택된 지점만 보이고, `InteractiveViewer`의
      `TransformationController` 스케일이 일정 값(1.8배) 이상으로 확대됐을
      때만 전부 표시한다 — 기본 화면을 깔끔하게 유지하면서 확대하면
      지역명이 드러나게 한다.
  - 지도 위에 겹치는 하단 바(`_BottomInfoBar`): 풍속 범례 + 시간
    스크러버(`Slider`, 2주치 `windFieldSeriesHours`) + 선택 지점의 현재
    스크러버 시각 기준 요약(풍향·풍속·파고·파주기 한 줄). 라벨은 "지금"이
    아니라 항상 실제 날짜·시간을 표시한다. 요약 줄을 탭하면
    `showModalBottomSheet` + `DraggableScrollableSheet`로 시간별 상세
    목록(`_DetailSheetContent`)이 위로 펼쳐진다(윈디에서 지점을 탭하면
    아래에 뜨는 예보 패널과 동일한 구조) — 목록에서 시각을 고르면 그
    시각으로 스크러버가 이동하고 시트가 닫힌다.
  - `WindField`: 위경도 격자(10×12)에 동서/남북 성분(u/v, m/s)을 저장, 쌍선형
    보간으로 임의 좌표의 바람 벡터를 조회 (`features/weather/data/models`).
  - `WindFieldSeries`: 같은 격자의 시간별 `WindField` 목록 — 시간 스크러버가
    가리키는 인덱스로 `.at(offset)` 조회.
  - `OpenMeteoWindFieldRepository`: `fetchField()`(현재 시점, `current` 파라미터)와
    `fetchSeries()`(48시간, `hourly` 파라미터)를 모두 지원. 격자점 80개를 콤마로
    묶어 각각 한 번의 요청으로 가져온다. 실패 시 `MockWindFieldRepository`
    (소용돌이 합성 바람장, 시간별 시드 변주)로 폴백.
  - `Ticker` 기반 파티클 220개가 벡터장을 따라 이동하며 궤적을 남기고
    (`WindMapPainter`), 지리 좌표 → 정규화 캔버스 좌표로 매 프레임 투영한다.
    이동 배율은 화면에서 보기 쉽도록 과장한 값이며 실제 이동 속도가 아니다.
  - 실제 지도 타일(해안선 등)이 필요해지면 `flutter_map` 오버레이로 확장 가능
    (현재는 그라디언트 배경 위에 벡터장만 표시하는 경량 버전).
  - ⚠️ `app/app.dart`의 `IndexedStack`은 4개 탭을 전부 마운트해 두므로, 날씨 탭이
    보이지 않을 때도 Ticker가 돌지 않도록 각 탭을 `TickerMode(enabled: 현재탭)`
    로 감싼다 — 빠뜨리면 `pumpAndSettle` 기반 위젯 테스트가 다른 탭에서도
    멈춘다(직접 겪은 문제).

### features/locations — 지역
- 전국 해안·낚시 포인트 41곳 (`sample_locations.dart`, 서해/남해/동해/제주).
  `khoaStationCode`가 있는 지점(9곳)만 조석 실데이터가 붙고, 나머지는 해역별
  합성 조석 곡선으로 대체된다 — 물때·해양 날씨·낚시지수는 좌표만 있으면
  지점 구분 없이 전부 동작한다.
- 지역 검색·선택·즐겨찾기 화면(`LocationsScreen`), 목록이 길어 `ListView.builder`로
  지연 렌더링.
- 선택된 지역은 앱 전역 상태(`selectedLocationProvider`)로 공유되어 tide/weather 화면이 반응

### features/home — 홈 대시보드 (v0.5 그래픽 개편)
- 상단 바다색 그라디언트 헤더: 지역명 + 우측 상단 지역 선택 버튼
  (`showLocationPickerSheet` — 검색 가능한 바텀시트, `LocationsScreen`과
  별개의 가벼운 진입점), 물때 요약, `HomeDateStrip`(좌우 스크롤 날짜 띠).
  - `HomeDateStrip`(`widgets/home_date_strip.dart`): 과거 2주~미래 2주
    (총 4주, `homeForecastPastDays`/`homeForecastFutureDays`)를 가로로
    넘기며 날짜를 고른다. 선택 시 자동으로 중앙 스크롤.
- 날짜별 요약 3종(색상 아이콘 카드): 물때(다음 만조/간조, 오늘이 아니면
  그 날짜의 첫 만조/간조 + 만조/간조 횟수), 해양 날씨(선택 날짜에 가장
  가까운 시간대 값 — 오늘은 지금 시각, 그 외엔 정오 기준),
  바다낚시지수(`FishingLevelBadge` — 등급색 배지 + 채움 막대. 예전 노란
  점 5개 표기가 스와이프 인디케이터처럼 보인다는 피드백으로 교체).
  - 기준 어종은 해역별 우선순위(`preferredSpeciesForRegion`)를 따른다:
    서해 = 쭈꾸미·갑오징어, 남해/동해 = 문어·광어·우럭. 데이터에 우선순위
    어종이 여러 종 있으면(`FishingForecast.speciesGroupsForDate`) 그 종을
    모두 카드에 나란히 표시한다(하나만 보여주던 것을 개편).
- `homeMarineForecastProvider`: 홈 전용 4주 예보(과거 14일 포함,
  Open-Meteo `past_days` 파라미터 사용). 날씨 탭의 `marineForecastProvider`
  (과거 데이터 없음, 기본 16일)와는 별도 provider라 서로 영향 없음.

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

DataGoKrFishingRepository implements FishingRepository          [구현됨]
  GET /1192136/fcstFishingv2/GetFcstFishingApiServicev2  (미리보기 URL 실측)
  파라미터: serviceKey/type=json/reqDate/gubun=갯바위/pageNo/numOfRows
  실측 확정 필드: seafsPstnNm(포인트)·lat/lot·predcYmd·predcNoonSeCd(오전/오후)
    ·seafsTgfshNm(어종)·totalIndex(5단계 라벨)·tdlvHrCn(물때)·min/maxWvhgt·Wtem
  하루 전체 포인트(~1,750건)를 받아 선택 지역 최근접 포인트로 필터링.
  키 주입 시 활성, 실패 시 합성 데이터 폴백.

DataGoKrTideRepository implements TideRepository                [구현됨]
  End Point: https://apis.data.go.kr/1192136/tideFcstHghLw  (활용신청 승인됨)
  - 고조/저조 극값만 제공하므로 전날~다음날 3일치를 조회한 뒤
    극값 사이를 코사인 보간해 차트용 25개 시간별 조위를 생성한다.
  - 응답 필드명은 KHOA 계열 명명 후보(camel/snake)를 허용하는 매퍼로 흡수,
    매핑 실패·네트워크 오류 시 합성 데이터로 폴백 (범위 위반은 폴백 안 함).
  - 키가 주입된 빌드(--dart-define=DATA_GO_KR_API_KEY=...)에서만 활성화.
  ※ 조석예보는 연간 조석표 기반이라 미래 1년 요구(FR-15)를 충족한다.
  ※ 첫 실기기 실행 시 실제 응답 필드명이 후보에 없으면 폴백으로 동작하므로,
    로그의 FormatException 메시지(필드 목록 포함)로 후보를 보강한다.
```

API 키(KHOA)는 `--dart-define=KHOA_API_KEY=...` 로 주입한다 (`core/config/env.dart`).
저장소에 키를 커밋하지 않는다 (NFR-04). Open-Meteo는 키가 필요 없다.

- 전환 방법: `tideRepositoryProvider` / `marineWeatherRepositoryProvider` 에서
  구현체만 교체한다. UI 코드는 변경 없음. 테스트는 provider override로 목을 주입한다.

### 캐싱·오프라인 설계 (FR-11, NFR-03)  [구현됨]

```
core/storage/cache_store.dart — CacheStore
  SharedPreferences 위에 JSON 문자열로 저장/조회하는 얇은 래퍼.
  키: "cache_v1_{feature}_{locationId}_{...}" (조석은 날짜, 낚시지수는 오늘 날짜 포함)

Caching{Tide,MarineWeather,Fishing}Repository — 데코레이터 패턴
  fetch 성공 → 즉시 CacheStore에 JSON 저장 후 반환
  fetch 실패(오프라인 등) → 같은 키로 캐시 조회, 있으면 그 값을 반환
  캐시도 없으면 원래 예외를 다시 던진다 (범위 초과 DataRangeException은
  캐시로 가리지 않고 그대로 전파 — 오프라인 문제가 아니므로).

배치: 실API → Caching 래퍼 → (실패 시) 캐시 → (그래도 없으면) 폴백 체인의
  outer wrapper(TideRepository/FishingRepository.withFallback,
  FallbackMarineWeatherRepository)가 합성 데이터로 최종 이어받는다.
  즉 "실데이터 → 오늘자 캐시 → 마지막 성공 캐시 → 합성 데이터" 순.
```

모델(TideDay/TideExtreme, MarineForecast/HourlyMarine, FishingForecast/
FishingIndex)에 `toJson`/`fromJson`을 추가해 캐시 직렬화에 사용한다.

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
| FR-12 (바람 지도) | `features/weather/presentation/weather_screen.dart`, `data/{models,repositories}/wind_field*` |
| FR-04 (물때 날짜 선택기) | `features/tide/presentation/widgets/tide_date_picker.dart` |
| FR-06 (전국 지역) | `features/locations/data/sample_locations.dart` |
| NFR-06 (품질) | `analysis_options.yaml`, `test/`, `.github/workflows/ci.yml` |

## iOS 확장 (NFR-01)

Dart 코드는 플랫폼 독립적이다. iOS 추가 시:
1. `flutter create --platforms ios .` 로 `ios/` 생성
2. 서명·번들 ID 설정 (`com.badamobile.app`)
3. 알림 등 플랫폼 기능 사용 시 iOS 권한 설정 추가
