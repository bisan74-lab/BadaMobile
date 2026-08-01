# BadaMobile (바다윈디)

Flutter 앱. 바다타임(물때·조석)과 윈디(바람·해양 날씨 지도)를 하나로 합친
무료 한국어 낚시/해양 앱. Android 우선, iOS 확장 전제.

**세부 설계·데이터 연동·화면별 책임은 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)를,
요구사항(FR/NFR)은 [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)를 먼저 읽는다.**
이 파일은 그 두 문서에 없는, 매번 반복되는 실전 규칙만 담는다.

## 자주 쓰는 명령

```bash
flutter analyze          # 커밋 전 필수, 이슈 0이어야 함
flutter test              # 전체 테스트(현재 87개)
dart format lib test       # 커밋 전 포맷
```

## 반드시 지킬 것

- **API 키 커밋 금지**: `--dart-define=DATA_GO_KR_API_KEY=...`로만 주입
  (`core/config/env.dart`). Open-Meteo는 키 불필요.
- **Repository는 항상 실API → 캐싱 → 폴백(합성 데이터) 체인**으로 조립한다.
  새 데이터 소스를 추가할 때도 이 패턴을 따른다.
- **지도 바람장은 서버 파일 우선**(`features/weather/.../github_wind_field_repository.dart`):
  GitHub Actions 크론(`.github/workflows/wind-data.yml` → `tool/fetch_wind.py`)이
  Open-Meteo에서 격자(현재 64×66≈0.62°, 4224점)를 배치로 받아 롤링 릴리스 `wind-data`의
  `wind_field.json.gz`(u/v를 cm/s int16 양자화)로 올리고, 앱은 그 파일 하나만
  내려받는다. 그래서 **사용자 기기는 Open-Meteo를 직접 다지점 호출하지 않아**
  분당 한도와 무관하고, 서버는 시간을 두고 배치로 받으므로 격자를 더 촘촘히
  뽑을 수 있다. 파일 실패 시 앱이 Open-Meteo 직접 호출→캐시→합성으로 폴백한다.
  파일 포맷을 바꾸면 `fetch_wind.py`와 `parseWindFieldFile`(및 그 테스트)을 함께
  맞춘다. **시간축도 비균일**(fmt 3): 앞 48시간은 1시간, 그 뒤는 3시간 간격이라
  `stepOffsets`(start로부터 경과 시간)를 담는다 — 균일 간격을 가정하면 시각이
  어긋난다. `caching_wind_field_repository`의 캐시 왕복도 이 배열을 보존해야
  한다. 수집 **간격**을 줄이는 건 의미가 없다(ECMWF가 하루 4번만 발표) —
  체감 신선도는 시간 해상도(`FINE_HOURS`)가 좌우한다.
- **서버 격자는 적응형(비균일)**: `fetch_wind.py`의 `_density_axis()`가 위·경도
  축마다 대한해협·서해·남해 연안(`LAT_FOCUS`/`LON_FOCUS`)에 밀도를 더 준
  비균일 좌표를 만든다(총점은 그대로, 핵심 해역만 더 촘촘히 재배치). 그래서
  파일엔 `latSteps`/`lonSteps` 외에 실제 축 좌표 배열 `lats`/`lons`(fmt 2)가
  들어 있고, `WindField`는 이걸 그대로 받아 **쌍3차(bicubic, 비균일 간격
  지원)**로 보간한다(`sample()`). `lats`/`lons`가 없는 구버전 파일·캐시는
  `WindField`가 `minLat`/`maxLat`/`latSteps`로 균일 격자를 재구성해 그대로
  동작한다(폴백 호환). 핵심 해역 범위를 바꾸면 `LAT_FOCUS`/`LON_FOCUS`/
  `DENSITY_BOOST`만 조정하면 된다.
- **히트맵엔 난류(turbulence) 도메인 워프를 얹는다**(`wind_heatmap.dart`의
  `_TurbulenceNoise`): 실제 모델 격자로는 다 담기 힘든 중규모 소용돌이를
  시각적으로 흉내 내려고, 색을 뽑을 좌표를 고정 시드 FBM 노이즈로 풍속에
  비례해 살짝 뒤튼다(무풍은 거의 그대로, 강풍일수록 더 흔들림). 실제 u/v
  값 자체는 바꾸지 않고 히트맵 렌더링에만 적용되며, 시드가 고정이라 시간이
  지나도 같은 위치는 같은 방식으로만 흔들려 지글거리지 않는다. 강도를
  바꾸려면 `_turbNoiseFreq`(소용돌이 크기)·`_turbMaxWarpDeg`(최대 뒤틀림)를
  조정한다.
- **홈·낚시정보 카드의 예보도 서버 파일 우선**
  (`features/weather/.../github_point_forecast_repository.dart`):
  `.github/workflows/point-forecast.yml` → `tool/fetch_points.py`가 3시간마다
  전국 지역(앱 `sample_locations.dart`를 파이썬이 그대로 읽는다)을 Open-Meteo
  다지점 요청 4번으로 모아 롤링 릴리스 `point-forecast`의
  `point_forecast.json.gz`(약 100KB)로 올린다. `OpenMeteoMarineRepository`는
  **지역 하나당 요청이 5번**(WAM 총파고·WAM 너울·GFS·수온·육상예보) 나가서
  새 지역마다 1~2초가 걸렸는데, 두 화면이 쓰는 건 날짜별 대표값 하나씩이라
  3시간 간격 파일이면 충분하다. **상세 예보 화면(`marineForecastProvider`)은
  이 파일을 쓰지 않는다** — 너울·파력이 필요하고 정밀도도 중요해서 직접
  호출을 유지한다. 파일에 없는 지역·다운로드 실패는 직접 호출로 폴백한다.
  값이 원본과 맞는지는 `tool/verify_points.py`가 표본 10곳을 같은 시각
  Open-Meteo와 대조해 확인하며, 수집 워크플로가 업로드 직후 함께 돌린다.
- **낚시지수도 서버 파일 우선**(`features/fishing/.../github_fishing_repository.dart`):
  GitHub Actions 크론(`.github/workflows/fishing-data.yml` → `tool/fetch_fishing.py`)이
  data.go.kr에서 전국 하루치를 모아 롤링 릴리스 `fishing-data`의
  `fishing_index.json.gz`(약 20KB)로 올리고, 앱은 그 파일 하나만 받는다.
  **이 API의 `numOfRows` 상한은 300이다** — 넘기면 HTTP 200에
  `resultCode: 10 INVALID_REQUEST_PARAMETER_ERROR`만 담긴 76B가 오고, 예전에
  3000으로 요청하다 늘 빈 응답을 받아 조용히 합성 데이터로 폴백했다(지역을
  바꿀 때마다 5~9초 걸리던 원인). 값을 바꿀 땐 `tool/probe_fishing.py`로
  실제 응답을 먼저 확인한다.
- **어종 목록은 API가 실제로 주는 것만 담는다**(`fishing_index.dart`의
  `fishingSpeciesCatalog`): 2026-08 실측 기준 감성돔·농어·돌돔·벵에돔·우럭·
  참돔 **6종이 전부**다. `gubun`을 바꿔도 늘지 않는다 — 유효값은 `갯바위`·
  `선상` 둘뿐이고 두 응답이 서로 같다(나머지는 INVALID_REQUEST_PARAMETER_ERROR).
  그래서 광어·문어·쭈꾸미·갑오징어는 이 API로 얻을 수 없고, 목록에 넣으면
  지수가 영영 빈칸이다. API가 함께 주는 `기타어종`(묶음)·`-`(빈 값)도
  `nonSpeciesLabels`로 걸러 화면·선택 목록에서 제외한다.
  `seasonalSpecies`·`preferredSpeciesForRegion`도 이 목록 안에서만 고른다
  (테스트가 강제한다). 목록을 바꿀 땐 `tool/probe_fishing.py`(mode=gubun)로
  실제 어종을 먼저 확인한다.
- **쭈꾸미·갑오징어·문어는 관측이 아니라 추정이다**
  (`fishing/data/models/jigging_estimate.dart`): 공공데이터에 이 어종 지수가
  없어서, 그날 조류 세기(`tideStrengthFraction` — 물때 화면 조류세기 막대와
  **같은 값**)와 지점 예보의 바람·돌풍·파고, 그리고 달별 제철 가중치로
  계산한다. 조류 선호 곡선은 **좌우 비대칭**이다(`slowTolerance` /
  `fastTolerance`) — 셋 다 바닥에 채비를 붙여 놓고 하는 낚시라 조류가 과한
  것이 없는 것보다 훨씬 해롭다. 대칭으로 두면 "정지"가 "급류"만큼 나쁘게
  나와 실제와 어긋난다. 갑오징어는 **약한 중간 > 정지 > 중간 > 급류** 순
  (사용자 실사용 경험).
  **추가 네트워크 호출이 없다** — 화면이 이미 갖고 있는 조위·예보만 쓴다.
  화면에는 반드시 **"추정" 배지**를 달아 관측 지수와 구분하고, 설정 >
  데이터 출처와 스토어 설명에도 추정임을 명시한다. 상수를 바꾸면
  `jigging_estimate_test.dart`가 선호 방향(느린 물/중간/넓게)을 지킨다.
- **어종 선택 목록은 그 지역에 값이 있는 어종만 보여준다**
  (`FishingForecast.availableSpecies`): 포인트마다 주는 어종이 달라서, 전체
  카탈로그를 그대로 띄우면 고르고도 빈칸이 나온다. 물때 화면·홈 화면의 선택
  UI 둘 다 이 집합으로 좁힌다(예보를 아직 못 받았으면 카탈로그 전체).
- **앱이 Open-Meteo를 직접 호출하는 경로(폴백)의 격자 총 좌표 수는 600 미만
  유지**(현재 21×24=504): 무료 한도가 분당 600콜이고 다지점 요청은 좌표
  1개=1콜이라, 넘기면 요청 한 번에 한도를 초과해 **매번 429 → 합성 폴백**이
  된다(837점으로 올렸다가 실제로 겪음). 색을 더 촘촘히 하려면 **서버 격자
  (`fetch_wind.py`의 LAT/LON_STEPS)를 올린다** — 서버는 배치로 나눠 받아 분당
  한도에 안 걸린다. 앱 직접호출 격자는 폴백이므로 504로 둔다.
- **서버 격자(`fetch_wind.py`)의 한 실행 총점은 5000 미만 유지**(현재
  64×66=4224): 서버는 배치·SLEEP로 분당 600콜은 피하지만 Open-Meteo엔
  **시간당 약 5000콜** 한도도 있어, 한 실행(≈15분)이 5000점을 넘으면 도중에
  429로 실패한다(0.5°/6399점으로 올렸다가 배치 5100 근처에서 겪음). 더 촘촘히
  하려면 실행을 시간 간격으로 쪼개야 하지, 한 실행 격자를 5000 넘기면 안 된다.
- **Ticker가 있는 화면(WeatherScreen)을 테스트할 때 `pumpAndSettle()` 쓰지
  말 것** — 계속 도는 애니메이션 때문에 멈추지 않는다. `pump()`로 프레임 수를
  지정해서 진행한다.
- **`app/app.dart`의 `IndexedStack`에 새 탭을 추가하면 `TickerMode(enabled:
  현재탭)`로 감싸야 한다** — 안 그러면 비활성 탭의 Ticker가 계속 돌아 다른
  탭 위젯 테스트가 멈춘다.
- 날씨 지도(`features/weather/presentation/`)의 `mapViewBounds`
  (`widgets/map_projection.dart`)와 **`OpenMeteoWindFieldRepository`의 격자
  범위(`minLat` 등)는 같은 bbox**(현재 위도 18~57, 경도 108~148 — 한국 중심에
  동아시아 주변국까지)를 써야 히트맵이 뷰를 정확히 채운다. 범위를 바꾸면
  `country_borders_data.dart`도 같은 bbox로 다시 뽑아야 한다(`tool/gen_coast.py`).
  이 파일은 **Natural Earth 10m 해안선·소형 섬·국경선·행정경계(주/성)·주요
  하천**(공개 도메인)을 bbox 클리핑·RDP 단순화해 자동 생성하며, 키별
  레이어(`해안선`·`국경`은 항상, `행정`·`강`은 확대 시)로 담는다
  (`CoastlinePainter`가 배율로 분기해 그린다). 제주·울릉도·외연도·다도해 등
  실제 섬이 그대로 들어 있다. 10m가 아니라 50m를 쓰면 섬이 대부분 빠지니 다시
  뽑을 때도 10m를 쓴다.
- 해안선·경계선(`CoastlinePainter`)과 도시 라벨(`MapCityLabelLayer`)은 **둘 다
  실제 WGS84 위경도**(Natural Earth 10m, 지명 좌표)를 그대로 쓴다.
  그래서 경도 보정 `kMapLonShift`(`map_projection.dart`)는 **0**이어야
  실제 지도와 맞고 서로도 정확히 겹친다 — 과거 -0.5°는 지금은 삭제된 항구
  점 마커에 맞추려던 오진단이었고, 해안선을 실제보다 서쪽으로 밀었다.
  값을 바꾸더라도 해안선·라벨은 **반드시 같은 값**을 써야 한다(한쪽만
  보정하면 라벨이 바다로 어긋난다). 지도에 항구 점은 없애고 라벨(rank별
  확대 단계 노출)만 지도 앱처럼 표시하며, `island:true` 항목(제주·울릉도·
  강화도·백령도 등)은 하늘색 마름모로 구분해 확대 시 바다 위 섬 이름도
  드러난다.
- **강제 업데이트 게이트**(`core/remote_config/`): `remote_config/app_gate.json`의
  `forceUpgrade`를 true로 바꾸면(앱 재배포 없이) 이미 설치된 모든 기기에서
  앱 실행이 막히고 업데이트 안내 화면(`ForceUpgradeScreen`)만 뜬다 — 무료
  버전을 나중에 광고 버전으로 전환할 때 쓴다. 배포 전 `Env.forceUpgradeConfigUrl`
  기본값(지금은 이 브랜치의 GitHub raw 경로)을 실제로 유지할 위치로 바꿔야
  하고, `app_gate.json`의 `storeUrl`도 실제 스토어 링크로 채워야 한다. 설정을
  못 받아오면(오프라인 등) 항상 앱을 정상 실행한다 — 이 폴백 규칙은 절대
  건드리지 않는다.

- **광고는 부가 기능이라 절대 앱을 막지 않는다**(`core/widgets/ad_placeholder.dart`):
  배너 로드에 실패하거나 광고가 꺼져 있으면 같은 높이의 앱 소개 박스로 조용히
  대체된다 — 이 폴백을 없애면 광고가 없을 때 레이아웃에 빈 칸이 생긴다.
  배너 자리는 물때·설정 두 곳이고 `AdSlot`으로 구분해 **화면마다 다른 광고
  단위**를 쓸 수 있다(설정용을 안 주입하면 물때용으로 폴백한다).
  광고 ID는 `Env.admobBannerAdUnitId`·`admobSettingsBannerAdUnitId`
  (dart-define)와 Gradle 환경변수
  `ADMOB_APP_ID`(AndroidManifest 플레이스홀더)로 **빌드 때 주입**하고,
  둘 다 기본값이 구글 공식 **테스트 ID**라 설정 없이 빌드해도 실 수익 계정에
  무효 트래픽이 잡히지 않는다. 실 ID는 저장소에 커밋하지 않는다.
  **위젯 테스트가 광고 플랫폼 채널을 건드리면 안 되므로** `adsRuntimeEnabled`
  기본값은 false이고 `main()`에서만 켠다 — 테스트에서 이 값을 켜지 말 것.

## 릴리스 빌드/전달

기기 확인용 APK와 스토어 제출용 AAB는 **워크플로가 다르다**:

| | `release-apk.yml` | `release-aab.yml` |
|---|---|---|
| 서명 | debug 키 | 업로드 키(Secret) |
| 광고 | 테스트 광고 | 실제 광고 ID(Secret) |
| 용도 | 기기에 설치해 확인 | Play Console 제출 |

실제 기기로 확인이 필요하면 로컬 Android SDK 없이도 GitHub Actions로 빌드한다:
`release-apk.yml`(workflow_dispatch)을 트리거 → 완료되면 GitHub Release
(`test-build-N` 태그)에서 `app-release.apk`를 받아 전달한다. Actions
아티팩트가 아니라 Release를 쓰는 이유는 문서에 있음.

릴리스 서명은 `android/key.properties`가 있을 때만 적용되고 없으면 debug 키로
폴백한다 — 이 폴백을 없애면 키가 없는 CI·새 클론에서 빌드가 깨진다.

**스토어 런칭 절차(계정 생성·ID 발급·Secret 등록·Play Console 등록)는
[docs/PLAY_STORE_LAUNCH.md](docs/PLAY_STORE_LAUNCH.md)에 정리돼 있다.**
