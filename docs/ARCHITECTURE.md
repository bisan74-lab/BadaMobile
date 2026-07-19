# BadaMobile 구조 설계

> 요구사항: [REQUIREMENTS.md](REQUIREMENTS.md) — FR/NFR ID를 본 문서에서 추적한다.

## 화면 구조와 흐름

```
AppShell (하단 탭, IndexedStack)
├── 홈        HomeScreen         FR-07   날짜별 물때/날씨/낚시지수 요약
├── 날씨      KmaWeatherScreen   FR-20   기상청 단기예보(육상) 일자별·시간별 예보
├── 물때      TideScreen         FR-01~04, 15~17   그래픽 물때 카드, 조위 그래프, 만조/간조 타임라인
├── Windy     WeatherScreen      FR-05, FR-12   화면 전체 바람 지도(윈디 스타일) + 하단 정보 바
└── 설정      SettingsScreen     FR-21   템플릿(스킨) / 정보(문의·버전·광고제거·약관)
```

- 지역 선택은 모든 탭 AppBar 우측의 `RegionSelectorAction`(현재 지역명 + 아이콘)에서
  공용 바텀시트(`showLocationPickerSheet`)로 연다. 지역탭은 없앴다.
- 지역 변경은 `selectedLocationProvider` 하나로 전파된다 — 화면 간 별도 네비게이션 연동 불필요.
- 새 기능은 `features/` 아래 새 디렉터리로 추가한다.
- `BadaMobileApp`(`app/app.dart`)은 `AppShell`을 띄우기 전에 강제 업데이트
  게이트(`appGateProvider`)를 확인한다 — 아래 참고.

## 강제 업데이트 게이트 (`core/remote_config/`)

무료 버전을 배포한 뒤 나중에 광고가 붙는 버전으로 전환할 때, **앱을
재배포하지 않고** 기존에 설치된 모든 기기의 실행을 막기 위한 장치다.

- `remote_config/app_gate.json`(이 저장소에 커밋된 정적 파일, GitHub raw로
  서빙)의 `forceUpgrade`를 `true`로 바꾸기만 하면 된다. 앱은 시작할 때마다
  `AppGateRepository.fetch()`로 이 JSON을 받아와 `forceUpgrade`가 true면
  `AppShell` 대신 `ForceUpgradeScreen`(업데이트 안내 + 스토어 링크 버튼)을
  띄우고, 뒤로가기로도 빠져나갈 수 없다.
- **실패 시 항상 앱을 정상 실행한다**(`AppGateConfig.disabled`로 폴백) —
  오프라인이거나 설정 서버에 문제가 있다고 해서 사용자를 막으면 안 되기
  때문이다. 5초 타임아웃, 네트워크 예외, 200이 아닌 응답, JSON 파싱 실패
  모두 이 폴백으로 처리된다.
- 설정 URL은 `Env.forceUpgradeConfigUrl`(`--dart-define=FORCE_UPGRADE_CONFIG_URL=...`
  로 재정의 가능). 실제 배포 전에는 기본값(이 브랜치의 GitHub raw 경로)을
  장기적으로 유지할 위치로 바꿔야 한다. `app_gate.json`의 `storeUrl`도
  실제 스토어 링크로 채워야 `ForceUpgradeScreen`의 버튼이 의미가 있다.
- 응답 바디는 서버가 charset을 명시하지 않아도 항상 UTF-8로 직접
  디코딩한다(`utf8.decode(res.bodyBytes)`) — 한글 메시지가 깨지지 않게.

## 설계 원칙

- **Feature-first 구조**: 화면·상태·데이터를 기능 단위(`tide`, `weather`, `locations`, `home`, `fishing`)로 묶는다.
- **Repository 패턴**: UI는 리포지토리 인터페이스에만 의존한다. 각 데이터 소스는
  `실API → 캐싱 데코레이터 → (실패 시) 폴백(합성 데이터)` 순으로 조립된다.
- **Riverpod**: Provider로 리포지토리를 주입하고 화면 상태를 관리한다.
  테스트에서 `ProviderScope(overrides: ...)`로 목을 주입한다.

## 레이어 구성

```
presentation (screens, widgets, providers)
        │  Riverpod Provider로 주입
        ▼
data (models, repository 인터페이스 + 구현: mock / 실API / caching / fallback)
```

## 기능별 책임

### features/tide — 조석·물때 (바다타임 영역)
- `TideRepository`: 지역·날짜의 만조/간조 이벤트와 시간별 조위 곡선 제공.
  `withFallback`은 관측소 코드 미보유(`Exception`, 합성 데이터로 자연스럽게 대체)와
  범위 초과(`DataRangeException`, 사용자에게 안내 카드로 표시)를 구분해서 처리한다.
- 물때(1물~15물, 조금/사리) 계산은 `core/utils/mul_ttae.dart`에서 근사 음력 기반으로 처리.
- 화면 구성(`tide_screen.dart`):
  - `TideDatePicker`(연도→월→일 계층 3단 가로 스크롤 선택기, `widgets/tide_date_picker.dart`).
    진입 시 오늘 날짜 기본 선택, 범위는 조석 ±1년 / 물때 2년.
  - `_TideGraphicBody`: 바다색 그라디언트 카드(날짜·음력일·물때 배지·`MoonPhaseIcon`·
    `TideCurrentStrengthBar`) → 상세 조위 그래프(`TideChart`, 항상 펼쳐진 상태) →
    날짜 이동 버튼 → 만조/간조 타임라인(`TideTimeline`) 순으로 배치.
  - `TideTimeline`(`widgets/tide_timeline.dart`): 0~24시 세로 축을 중앙에 두고 만조는
    왼쪽·간조는 오른쪽에 배치, 이전 극값 대비 증감(▲▼) 표시, 오늘이면 현재 시각선 표시.
  - `MoonPhaseIcon`: 월령을 0~1 위상으로 정규화해 달 모양을 `CustomPainter`로 그리는
    장식용 지표(정밀 천문 계산 아님).

### features/weather — 바람·해양 날씨 (윈디 스타일 지도)
- `MarineWeatherRepository`: 시간별 풍향·풍속·돌풍·파고·파주기·파향·수온·너울(swell)
  파고/주기 예보 제공. `HourlyMarine.wavePowerKw`는 파력(kW/m)을 심해 파에너지
  근사식 `0.49·H²·T`로 계산하는 파생값이다(별도 저장 안 함).
- `WeatherScreen`은 `Stack` 레이아웃이다(페이지 스크롤 아님): 지도(`_WindMapArea`)가
  `Positioned.fill`로 화면 전체를 차지하고, 하단 정보 바(`_BottomInfoBar`)가 그 위에
  겹쳐 뜬다. 지도를 스크롤 컨테이너 안에 두면 핀치 줌 제스처가 페이지 스크롤과
  충돌하므로 이 구조를 유지해야 한다.
- 지도는 `InteractiveViewer`로 항상 확대/축소·이동 가능(고정 상하한 `minScale 1`~
  `maxScale 6`, `boundaryMargin`은 기본값 `EdgeInsets.zero`라 지도 바깥 빈 배경이
  보이는 지점까지는 이동할 수 없다). 겹치는 레이어(아래→위):
  1. 풍속 색상 히트맵(`WindHeatmapPainter`, `widgets/wind_heatmap.dart`) — m/s→색상
     스케일(파랑→청록→초록→노랑→주황→빨강→자주). `buildWindHeatmapImage()`가
     144×108 래스터를 구워 시간 스크러버로 필드가 바뀔 때만 다시 굽는다(파티클
     프레임마다 굽지 않음).
  2. 실제 국경·해안선(`CoastlinePainter`, `country_borders_data.dart`) — Natural
     Earth 1:50m Admin 0 Countries(공개 도메인, nvkelso/natural-earth-vector)에서
     추출·단순화해 정적으로 내장. 런타임에 지도 타일을 받아오지 않는다.
  3. 파티클 흐름(`WindMapPainter`) — `Ticker` 기반 220개 입자가 바람 벡터를 따라
     이동하며 궤적을 남긴다. 궤적 길이는 그 지점 풍속에 비례(약함=짧은 점,
     강함=긴 흐름선, `_WeatherScreenState._onTick`의 `maxTrail` 계산).
  4. 도시 이름(`MapCityLabelLayer`, 서울·부산 등 상시 표시) + 지점 마커(41곳,
     `InteractiveViewer` 배율이 1.8배 이상일 때만 이름 표시). 도시/지점 라벨은
     둘 다 지도 배율만큼 `Transform.scale(1/scale)`로 반대 축소해 그려서,
     확대해도 글자 크기가 화면 기준으로 일정하게 유지된다(그대로 두면
     지도와 같이 커져서 글자가 지나치게 확대돼 보인다).
- `MapProjection`/`LatLonBounds`(`widgets/map_projection.dart`): 모든 레이어가
  공유하는 위경도↔캔버스 좌표 변환(역변환 `latFor`/`lonFor`은 지도 탭 좌표를
  위경도로 되돌릴 때 쓴다). 기본 화면뷰(`mapViewBounds`)는 대한민국이 중앙에 오도록
  잡았다. **바람장 격자 범위(`OpenMeteoWindFieldRepository.minLat` 등)와 반드시
  동일해야** 히트맵이 지도 전체를 채운다 — 둘 중 하나만 바꾸면 어긋난다. 좌표를
  바꾸면 `country_borders_data.dart`도 같은 범위로 재추출해야 한다(재추출 스크립트는
  세션 기록 참고, Natural Earth geojson을 bbox로 클리핑 후 포인트 밀도를 줄인다).
- 지도를 탭하면 그 **임의 좌표**에 핀이 꽂히고 "이 지점의 예보" 말풍선(`_PointCallout`)이
  뜬다(윈디의 forecast at this point). 말풍선을 누르면 그 좌표로 만든 즉석 `SeaLocation`
  (`pointSeaLocation`)으로 `marineForecastProvider`를 조회해, 하단에 붙는 **색상
  메테오그램 패널**(`_PointForecastPanel`/`_Meteogram`)을 띄운다. 상단에 시간 슬라이더,
  아래에 3시간 간격·향후 2주 가로 스크롤 표(행=시간·기온·바람·돌풍·파도·너울·너울주기·
  파력·수온). 바람은 `windSpeedColor`, 파도·너울은 `waveHeightColor`로 셀을 색칠해 세기를
  직관적으로 보여준다(윈디 메테오그램 참고). 탭이 즐겨찾기 지역을 바꾸지는 않는다.
- 하단 바(`_BottomInfoBar`, 일반 모드)는 풍속 범례 + 시간 스크러버(지도 애니메이션 시각) +
  선택 지점 요약을 보여주고, 요약을 탭하면 그 지역의 메테오그램 패널로 들어간다.
- 데이터 모델: `WindField`(위경도 격자 10×12에 u/v 저장, 쌍선형 보간) /
  `WindFieldSeries`(시간별 스냅샷, `.at(offset)`). `OpenMeteoWindFieldRepository`가
  다중좌표 요청(콤마 구분)으로 격자를 채우고, 실패 시 `MockWindFieldRepository`
  (소용돌이 합성 바람장, 같은 격자 범위/해상도)로 폴백.
- ⚠️ `app/app.dart`의 `IndexedStack`은 5개 탭을 전부 마운트해 두므로, 비활성 탭에서
  Ticker가 돌지 않도록 각 탭을 `TickerMode(enabled: 현재탭)`로 감싼다 — 빠뜨리면
  `pumpAndSettle` 기반 위젯 테스트가 다른 탭에서도 멈춘다.

### features/kma_weather — 날씨(육상 예보)
- Windy 탭(해양·바람 지도)과 별개인 지역 육상 날씨 탭. 화면 구성: 현재값 헤더 →
  오늘/내일 요약 → 2시간 강수 나우캐스트 → 24시간 예보(가로) → 7/15일 토글 목록 →
  상세 정보(바람·돌풍/습도/자외선/가시거리/일출몰/공기질).
- **데이터: 기상청 우선 + Open-Meteo 보조** (`weatherForecastProvider`). 뼈대는
  `OpenMeteoLandWeatherRepository`(Forecast API 16일 일별/시간별 + `minutely_15`
  2시간 강수 + Air-Quality API 공기질, 전 세계·키 불필요). **기상청 단기예보가
  조회되면**(`kmaWeatherRepositoryProvider`, `Env.dataGoKrApiKey` 필요) 근일(약 3일)
  시간별 기온·날씨를 그 값으로 덮어쓴다(`_overlayKma`, `kmaToWmo`로 SKY/PTY→WMO 환산).
  실패 시 캐시(`CachingLandWeatherRepository`) → 합성(`MockLandWeatherRepository`) 폴백.
- 날씨 표현은 WMO 코드(`weather_code.dart`)로 통일하고, 아이콘은 라이선스 없는
  직접 그린 `WeatherIcon`(`CustomPainter`, 해·구름·비·눈·번개 등)으로 그린다.
- 5분 갱신·기상특보(경보)는 무료 무키 소스가 없어 미지원(대신 2시간 강수 나우캐스트를 제공).

### features/settings — 설정
- **한 화면**에 세로로: 맨 위 **템플릿**(`ExpansionTile`, 기본 펼침) → 그 아래 **정보**.
- 템플릿 옵션: 앱 스킨=시드 색(`skinProvider`, `app_skin_id`), 밝기 모드
  시스템/라이트/다크(`themeModeProvider` → `MaterialApp.themeMode`, `theme_mode`),
  배경 그래픽 토글(`backdropEnabledProvider`, `sea_backdrop_enabled` — 물때 타임라인의
  `SeaBackdrop` 표시 여부). 모두 즉시 반영 + 영속화.
- 정보: 오류신고·사업제휴 문의 메일 `bisan74@gmail.com`, 앱 버전·릴리즈 날짜
  (`app_info.dart`), "광고 제거"(정식 배포 후 인앱 결제 예정, 현재는 안내),
  "정책 및 이용약관"(`PolicyScreen`, 책임 제한 약관).

### features/locations — 지역
- 전국 해안·낚시 포인트 41곳(`sample_locations.dart`, 서해/남해/동해/제주).
  `khoaStationCode`가 있는 지점(9곳)만 조석 실데이터가 붙고, 나머지는 해역별 합성
  조석 곡선으로 대체된다 — 물때·해양 날씨·낚시지수는 좌표만 있으면 전부 동작한다.
- 지역탭은 없앴다. 대신 모든 탭 AppBar 우측 `RegionSelectorAction`이 공용
  바텀시트 `showLocationPickerSheet`를 연다. 시트는 **현재 위치(GPS,
  `geolocator`→`resolveCurrentLocation`)** + **지명 검색(읍/면/동 단위,
  `GeocodingRepository`=Open-Meteo Geocoding 무료·키불필요→`geocodingSearchProvider`)**
  + 내장 지점 + 즐겨찾기를 한 화면에 제공한다.
- 공용 지역 `selectedLocationProvider`는 tide/home/Windy가 공유하고, **날씨 탭은
  별도의 `weatherLocationProvider`**를 쓴다 — 날씨 탭에서 내륙 지점을 골라도 물때·
  바다타임 등 다른 탭에 영향을 주지 않는다. `RegionSelectorAction(forWeather: true)`와
  `showLocationPickerSheet(forWeather: true)`로 대상 provider를 고른다.
- 두 provider 모두 선택을 **전체 정보(JSON)로 영속화**해 검색·현재위치 등 목록에 없는
  커스텀 지점도 재시작 후 복원된다(구버전 id-only 키 호환).
- **현재 위치(GPS)는 날씨 탭에만** 적용한다. 홈/물때/Windy는 공용 지역을 그대로 쓰며
  현재 위치와 연동하지 않는다. `AppShell._initLocation`은 날씨 탭 저장 위치가 없는 첫
  실행일 때만 권한을 요청해 `weatherLocationProvider`를 현재 위치로 채운다(거부·실패
  시 기본 지점 유지). "현재 위치로 설정" 버튼도 `forWeather` 시트에서만 노출된다.
- `SeaLocation.rank`(1=주요→3=소규모)로 Windy 지도 라벨을 확대 단계별 노출,
  `inland=true`(내륙 도시·검색 지점)는 지도 마커에서 제외. 마커 점은 투영 좌표에
  정확히 중심을 맞춰 해안선과 정렬된다.

### features/home — 홈 대시보드
- AppBar 제목 "바다 윈디" + 우측 `RegionSelectorAction`(현재 지역명 + 지역 선택).
- 상단 바다색 그라디언트 헤더: 물때 요약 + `HomeDateStrip`(좌우 스크롤 날짜 띠, 과거
  2주~미래 2주 총 4주, 선택 시 자동 중앙 스크롤).
- 날짜별 요약 3종(색상 아이콘 카드): 물때(다음 만조/간조, 오늘이 아니면 그 날짜의
  첫 만조/간조 + 횟수), 해양 날씨(선택 날짜에 가장 가까운 시간대 값 — 오늘은
  지금 시각, 그 외엔 정오 기준), 바다낚시지수(`FishingLevelBadge` — 등급색 배지 +
  채움 막대).
  - 기준 어종은 해역별 우선순위(`preferredSpeciesForRegion`)를 따른다: 서해 =
    쭈꾸미·갑오징어, 남해/동해 = 문어·광어·우럭. 데이터에 우선순위 어종이 여럿
    있으면(`FishingForecast.speciesGroupsForDate`) 모두 나란히 표시한다.
- `homeMarineForecastProvider`: 홈 전용 4주 예보(Open-Meteo `past_days`로 과거
  14일 포함). 날씨 탭의 `marineForecastProvider`(과거 데이터 없음, 기본 16일)와는
  별도 provider라 서로 영향 없음.

## 데이터 소스 연동 설계 (FR-08, FR-09)

- **해양 기상(바람·파고·파주기·수온)**: Open-Meteo Marine + Forecast API 채택 —
  무료, 키 불필요, `forecast_days` 최대 16일(FR-05 "최소 2주" 충족),
  `past_days`로 과거 최대 92일도 조회 가능. 검토했던 대안(Windy Point API는 유료,
  기상청 API는 예보기간이 2주 미달, NOAA 원자료는 자체 전처리 서버 필요)은 모두
  기각.
- **조석(만조/간조·조위)**: KHOA 바다누리 Open API(data.go.kr) 채택 — 연간
  조석표 기반이라 FR-15(±1년) 충족.
- **바다낚시지수**: data.go.kr `GetFcstFishingApiServicev2` — 하루 전체 포인트
  (~1,750건)를 받아 선택 지역 최근접 포인트로 필터링.

```
OpenMeteoMarineRepository implements MarineWeatherRepository   [구현됨]
  GET https://marine-api.open-meteo.com/v1/marine
      ?latitude&longitude&forecast_days=16&past_days=N(선택)
      &hourly=wave_height,wave_period,wave_direction,sea_surface_temperature
  GET https://api.open-meteo.com/v1/forecast
      ?latitude&longitude&forecast_days=16&wind_speed_unit=ms&past_days=N(선택)
      &hourly=wind_speed_10m,wind_gusts_10m,wind_direction_10m,temperature_2m
  두 응답을 시간축 기준으로 병합해 HourlyMarine[] 생성 (null은 직전 값으로 채움)

DataGoKrFishingRepository implements FishingRepository          [구현됨]
  GET /1192136/fcstFishingv2/GetFcstFishingApiServicev2
  파라미터: serviceKey/type=json/reqDate/gubun=갯바위/pageNo/numOfRows
  실측 필드: seafsPstnNm(포인트)·lat/lot·predcYmd·predcNoonSeCd(오전/오후)
    ·seafsTgfshNm(어종)·totalIndex(5단계 라벨)·tdlvHrCn(물때)·min/maxWvhgt·Wtem

DataGoKrTideRepository implements TideRepository                [구현됨]
  GET https://apis.data.go.kr/1192136/tideFcstHghLw
  고조/저조 극값만 제공하므로 전날~다음날 3일치를 조회한 뒤 극값 사이를
  코사인 보간해 차트용 25개 시간별 조위를 생성한다. 응답 필드명은 후보
  매퍼로 흡수하며, 매핑 실패·네트워크 오류 시 합성 데이터로 폴백
  (범위 위반 DataRangeException은 폴백하지 않고 그대로 전파).
```

- API 키는 `--dart-define=DATA_GO_KR_API_KEY=...`로 주입(`core/config/env.dart`),
  저장소에 커밋 금지(NFR-04). Open-Meteo는 키가 필요 없다.
- 실데이터/폴백 전환은 `tideRepositoryProvider` / `marineWeatherRepositoryProvider`
  / `fishingForecastProvider` 에서 구현체만 교체하면 된다. UI 코드는 변경 없음.
  테스트는 provider override로 목을 주입한다.

### 캐싱·오프라인 설계 (FR-11, NFR-03)

```
core/storage/cache_store.dart — CacheStore
  SharedPreferences 위에 JSON 문자열로 저장/조회하는 얇은 래퍼.
  키: "cache_v1_{feature}_{locationId}_{...}" (조석은 날짜, 낚시지수는 오늘 날짜 포함)

Caching{Tide,MarineWeather,Fishing}Repository — 데코레이터 패턴
  fetch 성공 → 즉시 CacheStore에 JSON 저장 후 반환
  fetch 실패(오프라인 등) → 같은 키로 캐시 조회, 있으면 그 값을 반환
  캐시도 없으면 원래 예외를 다시 던진다(범위 초과 DataRangeException은 캐시로
  가리지 않고 그대로 전파 — 오프라인 문제가 아니므로).

배치: 실API → Caching 래퍼 → (실패 시) 캐시 → (그래도 없으면) 폴백 체인의
  outer wrapper(TideRepository/FishingRepository.withFallback,
  FallbackMarineWeatherRepository)가 합성 데이터로 최종 이어받는다.
  즉 "실데이터 → 오늘자 캐시 → 마지막 성공 캐시 → 합성 데이터" 순.
```

모델(TideDay/TideExtreme, MarineForecast/HourlyMarine, FishingForecast/
FishingIndex)에 `toJson`/`fromJson`을 추가해 캐시 직렬화에 쓴다.

### 오류 처리 정책 (NFR-03)

- Repository는 실패 시 예외를 던지고, 화면은 `AsyncValue.when(error:)`에서 사용자용
  한국어 메시지로 변환해 표시한다.

## 상태 관리 규칙

- 전역 상태: 선택 지역, 즐겨찾기 → `locations/presentation/providers.dart`
- 화면 상태: `FutureProvider.family`로 (지역, 날짜) 등을 파라미터화해 비동기 로드
- 위젯은 가능한 한 `ConsumerWidget`으로 얇게 유지

## 테스트 전략

- `core/utils` 순수 함수(물때 계산 등)는 단위 테스트 필수
- 리포지토리 목 구현은 그 자체로 테스트 픽스처 역할
- 화면은 스모크 위젯 테스트(렌더링 + 핵심 텍스트/위젯 존재) 수준
- 지속 애니메이션(Ticker)이 있는 화면은 `pumpAndSettle()`이 아니라 `pump()`로
  몇 프레임만 진행해서 검증한다(계속 도는 Ticker에서 `pumpAndSettle`은 멈추지 않음)

## 모듈 의존 규칙

```
app/        → features/*  (화면 조립만)
features/A  → core/, shared/, 그리고 다른 feature의 "공개 provider"만
core/       → 외부 패키지만 (features를 알지 못함)
shared/     → core/ 만
```

- feature 간 직접 위젯 import는 지양하고, 공유가 필요한 상태는 provider로 노출한다.
  (현재 허용된 교차 의존: home → tide/weather/locations의 provider와 WindArrow)
- 순환 의존이 생기면 해당 모델/로직을 `core/`로 승격한다.

## 요구사항 추적 요약

| 요구사항 | 담당 모듈 |
|---|---|
| FR-01~04, 15~17 (물때/조석) | `features/tide`, `core/utils/mul_ttae.dart` |
| FR-05 (해양 예보) | `features/weather/data` |
| FR-06 (지역) | `features/locations`(공용 `RegionSelectorAction`/바텀시트) |
| FR-07 (홈 요약) | `features/home` |
| FR-08/09 (실데이터) | 각 feature `data/repositories/` |
| FR-12 (바람 지도) | `features/weather/presentation/` |
| FR-18 (낚시지수) | `features/fishing` |
| FR-20 (기상청 육상 예보) | `features/kma_weather` |
| FR-21 (설정: 템플릿/정보) | `features/settings` |
| NFR-06 (품질) | `analysis_options.yaml`, `test/`, `.github/workflows/ci.yml` |

## 빌드·배포

- CI(`ci.yml`): push/PR마다 format/analyze/test.
- 릴리스 APK(`release-apk.yml`, `workflow_dispatch`로 수동 실행): 실 API 키
  없이 빌드(합성 데이터로 동작) → GitHub Release에 `app-release.apk`를
  `test-build-{run_number}` 태그로 업로드. Actions 아티팩트(Azure Blob)가 아니라
  Release를 쓰는 이유는 일부 네트워크 환경에서 아티팩트 다운로드가 막히기 때문.

## iOS 확장 (NFR-01)

Dart 코드는 플랫폼 독립적이다. iOS 추가 시:
1. `flutter create --platforms ios .`로 `ios/` 생성
2. 서명·번들 ID 설정(`com.badamobile.app`)
3. 알림 등 플랫폼 기능 사용 시 iOS 권한 설정 추가
